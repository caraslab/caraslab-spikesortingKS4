function handle_binary_data(recnode_path, savedir_path, fid_data, fid_adc, data_channel_idx, adc_channel_idx, info_only)
    oebin_filedir = dir(fullfile(recnode_path, '**', '*.oebin'));

    batch_size = 1800000; % Lower this number if running out of memory

    % For file naming purposes
    cur_path = dir(savedir_path);
    
    all_data = load_open_ephys_binary(fullfile(oebin_filedir.folder, oebin_filedir.name), 'continuous', 1, 'mmap');

    data_channel_indeces = contains({all_data.Header.channels.channel_name}, 'CH');
    adc_channel_index = contains({all_data.Header.channels.channel_name}, 'ADC');

    % Weird bug in OpenEphys GUI sometimes names these differently
    % Tweak this mannually
    if sum(data_channel_indeces) == 0
        disp(['No channels named CH; tweak mannually (Lines 277,278)'])
        allchan = [data_channel_idx adc_channel_idx];
        data_channel_indeces = ismember(allchan, data_channel_idx);
        adc_channel_index = ismember(allchan, adc_channel_idx);
    end


    %% Read data channels and add to .dat
    if ~info_only
        fprintf('Concatenating data channels in chunks:\n')
        eof = 0;
        chunk_counter = 1;
        t1 = 1;
        while ~eof
            disp(['Chunk counter: ' num2str(chunk_counter) '...']);
            t2 = t1 + batch_size - 1;  % Update t2
            disp(['Reading data channels...']);
    
            if t2 < length(all_data.Timestamps)
    
                rawsig = all_data.Data.Data(1).mapped(data_channel_indeces, t1:t2);
            else
                rawsig = all_data.Data.Data(1).mapped(data_channel_indeces, t1:end);
                eof = 1;
            end
            disp(['Writing to file...']);
            fwrite(fid_data, rawsig, 'int16');
            t1 = t2 + 1;  % Update t1
            chunk_counter = chunk_counter + 1;
        end
        fclose(fid_data);
    
        %% Read ADC channels and add to .dat
        if ~isempty(adc_channel_index)
            fprintf('Concatenating ADC channels in chunks in the following order:\n')
            eof = 0;
            chunk_counter = 1;
            t1 = 1;
            while ~eof
                disp(['Chunk number: ' num2str(chunk_counter) '...']);
                t2 = t1 + batch_size - 1;  % Update t2
                disp(['Reading ADC channels...']);
                if t2 < length(all_data.Timestamps)
                    rawsig = all_data.Data.Data(1).mapped(adc_channel_index, t1:t2);
                else
                    rawsig = all_data.Data.Data(1).mapped(adc_channel_index, t1:end);
                    eof = 1;
                end
    
                disp(['Writing to file...']);
                fwrite(fid_adc, rawsig, 'int16');
                t1 = t2 + 1;  % Update t1
                chunk_counter = chunk_counter + 1;
            end
            fclose(fid_adc);
        end
    
        clear rawsig cur_ch_data;
    end
    
    %% Read DAC channels; Bundle in a .info file and output as CSV
    % unpack them in the behavior pipeline; this struct is meant to
    % look somewhat similar to the TDT epData that comes out of Synapse

    % For Rig2 with ePsych:
    % 0: DAC1 = sound on/off
    % 1: DAC2 = spout on/off
    % 2: DAC3 = trial start/end
    fprintf('Reading Events channels:\n')
    dac_data = load_open_ephys_binary(fullfile(oebin_filedir.folder, oebin_filedir.name), 'events', 1);
    events_filename = fullfile(savedir_path, [cur_path.name '.info']);

    epData.event_states = uint16(dac_data.Data) ./ dac_data.ChannelIndex;
    epData.event_ids = dac_data.ChannelIndex;  % convert to 1-base index
    epData.timestamps = double(dac_data.Timestamps - all_data.Timestamps(1)) / dac_data.Header.sample_rate; % Zero TTL timestamps based on the first sampled data  time
    epData.info.blockname = cur_path.name;

    % Grab date and timestamp from info
    block_date_timestamp = info.header.date_created;
    block_date_timestamp = datevec(block_date_timestamp, 'dd-mmm-yyyy HH:MM:SS');
    epData.info.StartTime = block_date_timestamp;  % TDT-like

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
            [cur_path.name '_DAC' int2str(cur_event_id) '.csv']), 'w');

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