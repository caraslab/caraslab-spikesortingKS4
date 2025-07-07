function caraslab_concatenate_sameDay_recordings(root_path, chanMap, recording_type)
%
% This function searches the recording folders and concatenates *CLEAN.dat files
% within folders that have the same date. A new file and directory will be
% created with Date_concat name (e.g. 201125_concat).

% For this to work, the foldernames have to have the date and session in
% them, which is the TDT naming convention. This function will order the
% recordings first by time recorded (in the foldername)

% The outputs are a concatenated .dat file and a .csv file listing the
% breakpoints (in samples) at which the original recordings ended. This file is
% important to realign spout and stimulus timestamps which start at 0

% Written by M Macedo-Lima October, 2020
% Last patch by M Macedo-Lima August, 2021


%Prompt user to select folder
datafolders_names = uigetfile_n_dir(root_path,'Select data directory');
datafolders = {};
for i=1:length(datafolders_names)
    [~, datafolders{end+1}, ~] = fileparts(datafolders_names{i});
end

% Remove SUBJ ID from folder names
subj_in_filename = 0;
for i = 1:length(datafolders)
    if contains(datafolders{i}, 'SUBJ-ID')
        subj_in_filename = 1;
        df = split(datafolders{i}, '_');
        id = df{1};
        datafolders{i} = append(df{2},'_',df{3},'_',df{4});
    end
end

% DEPRECATED: Sort according to dates and times in folder names
% date_time = regexp(datafolders, '\d+', 'match');
% recording_dates = [];
% recording_times = [];
% try
%     for i=1:length(date_time)
%     	switch recording_type
%             case 'synapse'
% 		       recording_dates = [recording_dates str2num(date_time{i}{1})];
% 		       recording_times = [recording_times str2num(date_time{i}{2})];
%             case 'intan'
%                 % Match synapse date format
%                 cur_recording_date = cell2mat(date_time{i}(1:3));
%                 recording_dates = [recording_dates str2num(cur_recording_date(3:end))];
%                 recording_times = [recording_times str2num(cell2mat(date_time{i}(4:end)))];
%         end
%     end
% catch ME
%     if strcmp(ME.identifier, 'MATLAB:badsubscript')
%         fprintf('\nfile not found\n')
%         return
%     else
%         fprintf(ME.identifier)
%         fprintf(ME.message)
%         return
%     end
% end

% % now sort hierarchically first date, then time
% temp_cell = horzcat(datafolders', num2cell([recording_dates' recording_times']) );
% temp_cell = sortrows(temp_cell, [2 3]);
% datafolders = temp_cell(:,1)';

% Sort according to dates and times in ePsych metadata
recording_date_time = {};
for i = 1:length(datafolders)
    cur_ops = load(fullfile(root_path, datafolders{i}, 'config.mat'));
    cur_metadata = cur_ops.ops.epsych_metadata{1};
    recording_date_time{end+1} = datetime(cur_metadata.StartTime);
end
recording_date_time = [recording_date_time{:}];
[recording_date_time, sort_idx] = sort(recording_date_time);
datafolders = datafolders(sort_idx);

unique_days = unique(string(recording_date_time, 'yyMMdd'));
for day_idx=1:length(unique_days)
    cur_day = unique_days(day_idx);
    cur_day_finder = string(recording_date_time, 'yyMMdd') == cur_day;
    % switch recording_type
    %     case 'synapse'
    %         cur_day_datafolders = strfind(datafolders, num2str(unique_days(day_idx)));
    %     case 'intan'
    %         cur_day_datafolders = strfind(datafolders, datestr(datevec(num2str(unique_days(day_idx)), 'yyyymmdd'), 'yyyy-mm-dd'));
    % end
    % cur_day_datafolders = datafolders(~cellfun('isempty', cur_day_datafolders));
    cur_day_datafolders = datafolders(cur_day_finder);
    
    %Skip if cur_day only has 1 recording
    if length(cur_day_datafolders) == 1
        continue
    end
    
    output_dir = strcat(unique_days(day_idx), "_concat");
    
    output_file_name = output_dir;
    
    % Print names of files to check order
    fprintf('\nConcatenating files in the following order:\n')
    for i = 1:length(cur_day_datafolders)
        fprintf('\t%s\n',cur_day_datafolders{i}) % print each file to make sure it's in order
        % need the sorting performed above!!!
    end

    full_output_dir = fullfile(root_path, output_dir);
    mkdir(full_output_dir);
    
    fidC = fopen(fullfile(full_output_dir, strcat(output_file_name, "_CLEAN.dat")),  'w'); % Write concatenated recording
    session_names = {};
    break_points = [];
	break_points_seconds = [];
    tranges = [];
    cumulative_tranges =[];
    badchannels = [];
    t0 = tic;
    for i = 1:numel(cur_day_datafolders)
        cur_path_name = cur_day_datafolders{i};
        
        if subj_in_filename == 1
            cur_path_name = append(id, '_', cur_path_name);
            cur_sourcedir = fullfile(root_path, cur_path_name);
        else
            cur_sourcedir = fullfile(root_path, cur_path_name);
        end

        %Load in configuration file (contains ops struct)
        % Catch error if -mat file is not found
        try
            load(fullfile(cur_sourcedir, 'config.mat'));
        catch ME
            if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
                fprintf('-mat file not found\n')
                continue
            else
                fprintf(ME.identifier)
                fprintf(ME.message)
                continue
            end
        end

        NchanTOT = ops.NchanTOT;
        NT = ops.NT;
        badchannels = [badchannels ops.badchannels];

        fprintf('\tReading raw file: %s\n', ops.fclean)
        fid = fopen(ops.fclean, 'r'); % open current raw data

        session_names{end+1} = dir(ops.fclean).name;

        if i > 1
            previous_breakpoint = break_points(i-1);
        else
            previous_breakpoint = 0;
        end

		cur_break_point = get_file_size(ops.fclean)/NchanTOT/2 + previous_breakpoint;

        break_points = [break_points; cur_break_point];
		break_points_seconds = [break_points_seconds; cur_break_point/ops.fs];

        % create offset variables relevant to the concatenation process
        tranges = [tranges; ops.trange];
        cumulative_tranges = [cumulative_tranges; ops.trange + (previous_breakpoint / ops.fs)];
%         
        while ~feof(fid)  % read until end of file
            buff = fread(fid, [NchanTOT NT], '*int16'); % read and reshape. Assumes int16 data (which should perhaps change to an option)
            fwrite(fidC, buff(:), 'int16'); % write this batch to concatenated file
        end
        
        fclose(fid); % close the file
            
        % Make copies of the behavioral timestamps and metadata (if they exist) into the
        % Info files folder
        % In case this folder is still absent
        mkdir(fullfile(full_output_dir, 'Info files'));
        
        % find spout file
        spout_filename = dir(fullfile(cur_sourcedir, 'Info files', '*spoutTimestamps.csv'));
        if ~isempty(spout_filename)
            copyfile(fullfile(spout_filename.folder, spout_filename.name), fullfile(full_output_dir, 'Info files', spout_filename.name));
        end
        
         % find trial info file
        trialInfo_filename = dir(fullfile(cur_sourcedir, 'Info files', '*trialInfo.csv'));
        if ~isempty(trialInfo_filename)
            copyfile(fullfile(trialInfo_filename.folder, trialInfo_filename.name), fullfile(full_output_dir, 'Info files', trialInfo_filename.name));
        end
        
         % find metadata file
        metadata_filename = dir(fullfile(cur_sourcedir, 'Info files', '*ePsychMetadata.mat'));
        if ~isempty(metadata_filename)
            copyfile(fullfile(metadata_filename.folder, metadata_filename.name), fullfile(full_output_dir, 'Info files', metadata_filename.name));
        end
    end
    
    %% Output csv breakpoints
    
    % DEPRECATED: Grab subject name; this is specific for my naming convention; 
    % Should be tweaked if yours is different
    % cur_path_name = cur_day_datafolders{1};
    % cur_path = fullfile(root_path, cur_path_name);
    % split_dir = split(cur_path, filesep); 
    % 
    % subj_id = split(split_dir{end-1}, '-');
    % subj_id = join(subj_id(1:3), '-'); 
    % subj_id = subj_id{1}; 

    % Grab subject name from ePsych metadata
    subj_id = cur_metadata.Name;  % "Leftover" metadata from date sorting loop

    ret_table = cell2table(session_names', 'VariableNames', {'Session_file'});
    ret_table.Break_point = break_points;
	ret_table.Break_point_seconds = break_points_seconds;
    writetable(ret_table, fullfile(full_output_dir, 'Info files', strcat(subj_id, '_', output_file_name, '_breakpoints.csv')));
    
    %% Close file and save Config
    fclose(fidC);
    
    % Create new config.mat
    caraslab_createconfig(root_path,chanMap, unique(badchannels), 0, recording_type, full_output_dir)
    load(fullfile(full_output_dir, 'config.mat'));
    ops.concat_tranges = tranges;
    ops.concat_cumulative_tranges = cumulative_tranges;
    
    save(fullfile(full_output_dir, 'config.mat'), 'ops');

    
    
    tEnd = toc(t0);
    fprintf('Done in: %d minutes and %f seconds\n', floor(tEnd/60), rem(tEnd,60));
end
