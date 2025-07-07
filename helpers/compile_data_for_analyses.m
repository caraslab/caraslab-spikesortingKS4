 function compile_data_for_analyses(root_path)
%
% This function loops through recording folders and extracts all relevant
% files into a folder called Data inside the parent directory. The purpose
% is to centralize all subjects' data into common directories
%


%Prompt user to select folder
datafolders_names = uigetfile_n_dir(root_path,'Select data directory');
datafolders = {};
for folder_idx=1:length(datafolders_names)
    [~, datafolders{end+1}, ~] = fileparts(datafolders_names{folder_idx});
end


% Create data analysis folders in parent directory
root_path_split = split(root_path, filesep);
parent_path = strjoin(root_path_split(1:end-1), filesep);
    
behavior_targetSource_paths =       {fullfile(parent_path, 'Data', 'Behavioral performance'), ...
                                        fullfile(root_path, 'Behavior')};
unitSurvival_targetSource_path =    {fullfile(parent_path, 'Data', 'Unit tracking'), ...
                                        fullfile(root_path, 'Unit tracking', '*_unitSurvival.csv')};
                                    
%For each data folder...
for folder_idx = 1:numel(datafolders)
        
    cur_path.name = datafolders{folder_idx};
    cur_bin_path = fullfile(root_path, cur_path.name);
    cur_ks_path = fullfile(cur_bin_path, 'kilosort4');
    cur_wfspiketimes_path = fullfile(cur_ks_path, 'Spike times');
    cur_wfinfo_path = fullfile(cur_ks_path, 'Waveforms info');

    % Declare all files you want to copy here
    % Behavior
    breakpoints_targetSource_paths =          {fullfile(parent_path, 'Data', 'Breakpoints'), ...  % Target
                                            fullfile(cur_bin_path, 'Info files', '*breakpoints.csv')};  % Source
    trialInfo_targetSource_path =             {fullfile(parent_path, 'Data', 'Key files'), ...
                                            fullfile(cur_bin_path, 'Info files', '*trialInfo.csv')};
    spoutTimestamps_targetSource_path =       {fullfile(parent_path, 'Data', 'Key files'), ...
                                            fullfile(cur_bin_path, 'Info files', '*spoutTimestamps.csv')};
    dacFiles_targetSource_path =              {fullfile(parent_path, 'Data', 'DAC files'), ...
                                            fullfile(cur_bin_path, 'Info files', '*DAC*.csv')};

    % Kilosort
    qualityMetrics_targetSource_path =        {fullfile(parent_path, 'Data', 'Quality metrics'), ...
                                            fullfile(cur_wfinfo_path, '*quality_metrics.csv')};
    shankWaveform_targetSource_path =         {fullfile(parent_path, 'Data', 'Quality metrics'), ...
                                            fullfile(cur_wfinfo_path, '*shankWaveforms*.pdf')};
    spikeTimes_targetSource_path =            {fullfile(parent_path, 'Data', 'Spike times'), ...
                                            fullfile(cur_wfspiketimes_path, '*cluster*.txt')};
    waveormMeasurements_targetSource_path =   {fullfile(parent_path, 'Data', 'Waveform measurements'), ...
                                            fullfile(cur_wfinfo_path, '*waveform_measurements.csv')};
    waveformFiles_targetSource_path =         {fullfile(parent_path, 'Data', 'Waveform samples'), ...
                                            fullfile(cur_wfinfo_path, '*_waveforms.csv')};

    % Combine to loop and copy
	all_paths = {breakpoints_targetSource_paths, ...
        trialInfo_targetSource_path, spoutTimestamps_targetSource_path, qualityMetrics_targetSource_path, shankWaveform_targetSource_path, ...
        spikeTimes_targetSource_path, waveormMeasurements_targetSource_path, dacFiles_targetSource_path, waveformFiles_targetSource_path};
    
    for path_idx = 1:length(all_paths)
        cur_paths = all_paths{path_idx};
        copy_data_files_from_dir(cur_paths{1}, cur_paths{2})
    end
    
end

% Lastly copy behavior and unit tracking files
copy_data_files_from_dir(behavior_targetSource_paths{1}, behavior_targetSource_paths{2})

copy_data_files_from_dir(unitSurvival_targetSource_path{1}, unitSurvival_targetSource_path{2})
