function handle_oe_data(recnode_path, savedir_path, data_filename, ...
    adc_filename, data_channel_idx, adc_channel_idx, info_only)
    % Data channels have the naming convention *CHXX.continuous
    % Read recording info to get channel order; ADC channels will also
    % be in the mix; Channels should come out in order

    batch_size = 1800000; % Lower this number if running out of memory

    try
        % OpenEphys before v1.0 (circa v0.5)
        session_info = get_session_info(recnode_path); 
        % Find the index of the recording node (assume only one)
        node_idx = find(contains(session_info.processors(:,2),'Filters/Record Node'));
        
        % Something weird happens sometimes
        all_channels = session_info.processors{node_idx, 3}{1};
        if isempty(all_channels)
            all_channels = session_info.processors{node_idx, 3}{2};
        end
    
        data_channels = all_channels(contains(all_channels,'CH'));
        adc_channels = all_channels(contains(all_channels,'ADC'));
    
        % Weird bug in OpenEphys GUI sometimes names these differently
        % Tweak this mannually
        if isempty(data_channels)
            disp('No channels named CH; Channel numbers need to be specified manually.')
            if isempty(data_channel_idx)
                disp('Please provide array with data channel numbers, e.g. 1:64')
                return
            end
    
            data_channels = all_channels(data_channel_idx);
            adc_channels = all_channels(adc_channel_idx);
        end


    catch ME
        if strcmp(ME.identifier, 'MATLAB:structRefFromNonStruct')
            fprintf('\tOld OpenEphys format reading failed. Attempting to read new format...\n')
            all_channels = dir(fullfile(recnode_path, '*.continuous'));
            all_channels = natsort({all_channels.name});
        
            data_channels = all_channels(contains(all_channels,'CH'));
        
            adc_channels = all_channels(contains(all_channels,'ADC'));
        
            % Weird bug in OpenEphys GUI sometimes names these differently
            % Tweak this mannually
            if isempty(data_channels)
                disp('No channels named CH; Make sure you provided channel numbers')
                if isempty(data_channel_idx)
                    disp('Please provide array with data channel numbers, e.g. 1:64')
                    return
                end
        
                data_channels = all_channels(data_channel_idx);
                adc_channels = all_channels(adc_channel_idx);
            end
        else
            rethrow(ME)
        end
    end

    % For file naming purposes
    [~, cur_path] = fileparts(savedir_path);

    %% Read data channels and add to a .dat file
    if ~info_only
        fprintf('Processing data channels in chunks:\n')
        % load one channel just to gauge data size
        temp_ch = load_open_ephys_data(fullfile(recnode_path, data_channels{1}));
        data_size = length(temp_ch);
        Nbatch = ceil(data_size / batch_size); % number of data batches
        eof = 0;
        batch_counter = 1;
        t1 = 0;  % sample '0' is the start of the file
        fprintf('\tProcessing %d batches.......\n', Nbatch)
        lineLength_toUpdate = 0;
        fid_data = fopen(data_filename,'w');
        while ~eof
            rawsig = zeros(length(data_channels), batch_size);  % preallocate
            t2 = t1 + batch_size;  % Update t2
            for ch_idx=1:length(data_channels)
                [cur_ch_data, ~, ~, is_eof] = load_open_ephys_data_chunked(fullfile(recnode_path, data_channels{ch_idx}), t1, t2, 'samples');
                rawsig(ch_idx, 1:length(cur_ch_data)) = cur_ch_data';
                if is_eof
                    eof = 1;
                    % trim the trailing zeros from rawsig
                    rawsig = rawsig(:, 1:length(cur_ch_data));
                end
            end
            fwrite(fid_data, rawsig, 'int16');
            t1 = t2;  % Update t1
    
            % Update last line in console as a poor-man's progress bar
            fprintf(repmat('\b',1,lineLength_toUpdate));
            lineLength_toUpdate = fprintf('\tCompleted %d out %d of batches.......\n', batch_counter, Nbatch);
            batch_counter = batch_counter + 1;
        end
        fclose(fid_data);
    
        %% Read ADC channels and add to a .dat file
        if ~isempty(adc_channels)
            fprintf('Processing ADC channels...\n')
            fid_adc = fopen(adc_filename,'w');
            % load one channel just to gauge data size
            eof = 0;
            batch_counter = 1;
            t1 = 0;  % sample '0' is the start of the file
            fprintf('\tProcessing %d batches.......\n', Nbatch)
            lineLength_toUpdate = 0;
            while ~eof
                rawsig = zeros(length(adc_channels), batch_size);  % preallocate
                t2 = t1 + batch_size;  % Update t2
                for ch_idx=1:length(adc_channels)
                    [cur_ch_data, ~, ~, is_eof] = load_open_ephys_data_chunked(fullfile(recnode_path, adc_channels{ch_idx}), t1, t2, 'samples');
                    rawsig(ch_idx, 1:length(cur_ch_data)) = cur_ch_data';
                    if is_eof
                        eof = 1;
                        % trim the trailing zeros from rawsig
                        rawsig = rawsig(:, 1:length(cur_ch_data));
                    end
                end
                fwrite(fid_adc, rawsig, 'int16');
                t1 = t2;  % Update t1
    
                % Update last line in console as a poor-man's progress bar
                fprintf(repmat('\b',1,lineLength_toUpdate));
                lineLength_toUpdate = fprintf('\tCompleted %d out %d of batches.......\n', batch_counter, Nbatch);
                batch_counter = batch_counter + 1;
            end
            fclose(fid_adc);
        end
    
        clear rawsig cur_ch_data temp_ch;
    end
    
    %% Read DAC channels; Bundle in a .info file and output as CSV
    % unpack them in the behavior pipeline; this struct is meant to
    % look somewhat similar to the TDT epData that comes out of Synapse

    % For Rig2 with ePsych:
    % 0: DAC1 = sound on/off
    % 1: DAC2 = spout on/off
    % 2: DAC3 = trial start/end
    fprintf('Reading Events channels:\n')
    events_filename = fullfile(savedir_path, [cur_path '.info']);

    try
        % OpenEphys before v1.0 (circa v0.5)
        % Load only a little bit of a channel file to get the zero timestamp info
        [~, data_timestamps, ~, ~] = load_open_ephys_data_chunked(fullfile(recnode_path, data_channels{1}), 0, 5, 'samples');
    
        [event_ids, timestamps, info] = load_open_ephys_data_faster(fullfile(recnode_path, 'all_channels.events'));
        epData.event_ids = event_ids + 1;  % Convert to 1-base index
        epData.event_states = info.eventId;
        epData.timestamps = timestamps - data_timestamps(1); % Zero TTL timestamps based on the first sampled data  time
        epData.info.blockname = cur_path;
    
        % Grab date and timestamp from info
        block_date_timestamp = info.header.date_created;
        block_date_timestamp = datevec(block_date_timestamp, 'dd-mmm-yyyy HH:MM:SS');
        epData.info.StartTime = block_date_timestamp;  % TDT-like
    catch ME
        if strcmp(ME.identifier, 'MATLAB:FileIO:InvalidFid')
            % OpenEphys v1.0+
            event_file_dir = dir(fullfile(recnode_path, '*RhythmData.events'));
            
             [events.sampleNumber, events.processorId, events.state, events.channel, events.header ] = ...
                loadEventsFile(fullfile(recnode_path, event_file_dir.name), 1);
            
            % Convoluted way to get the sampling rate
            info = readstruct(fullfile(recnode_path, 'settings.xml'), "FileType", "xml");
            sampling_rate = info.SIGNALCHAIN.PROCESSOR(1).STREAM.sample_rateAttribute;
        
            % Add some recording params and events to epData (Synapse data format)
            epData.streams.RSn1.fs = sampling_rate;
            epData.streams.RSn1.channels = 1:length(data_channels);
            
            epData.event_ids = events.channel + 1; % convert to 1-base index
            epData.event_states = events.state;
        
            epData.timestamps = double(events.sampleNumber)/sampling_rate;
            epData.info.blockname = cur_path;
        
            % Grab date and timestamp from info
            block_date_timestamp = info.INFO.DATE;
            block_date_timestamp = datevec(block_date_timestamp, 'dd mmm yyyy HH:MM:SS');
            epData.info.StartTime = block_date_timestamp;  % TDT-like
        else
            rethrow(ME)
        end
    end

    save(events_filename, 'epData','-v7.3');

    % Output each channel with events as separate csv with onset,
    % offset and duration
    unique_dacs = unique(epData.event_ids);
    for cur_event_id_idx=1:length(unique_dacs)
        cur_event_id = unique_dacs(cur_event_id_idx);
        cur_event_mask = epData.event_ids == cur_event_id;
        cur_event_states = epData.event_states(cur_event_mask);            
        cur_timestamps = epData.timestamps(cur_event_mask);

        cur_onsets = cur_timestamps(cur_event_states == 1);
        cur_offsets = cur_timestamps(cur_event_states == 0);

        % Handle DAC exceptions here
        % Skip DAC if either onset or offset are completely absent
        if isempty(cur_onsets) || isempty(cur_offsets)
            continue
        end

        % Remove first offset if lower than first onset 
        if cur_offsets(1) < cur_onsets(1)
            cur_offsets = cur_offsets(2:end);
        end

        % Remove last onset if length mismatch
        if length(cur_onsets) ~= length(cur_offsets)
            cur_onsets = cur_onsets(1:end-1);
        end

        % Calulate durations
        cur_durations = cur_offsets - cur_onsets;

        % Convert to table and output csv

        fileID = fopen(fullfile(savedir_path, 'CSV files', ...
            [cur_path '_DAC' int2str(cur_event_id) '.csv']), 'w');

        header = {'Onset', 'Offset', 'Duration'};
        fprintf(fileID,'%s,%s,%s\n', header{:});
        nrows = length(cur_onsets);
        for idx = 1:nrows
            output_cell = {cur_onsets(idx), cur_offsets(idx), cur_durations(idx)};

            fprintf(fileID,'%f,%f,%f\n', output_cell{:});
        end
        fclose(fileID);

    end
end
