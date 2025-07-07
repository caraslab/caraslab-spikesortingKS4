function plot_autocorrelograms(root_path, show_plots, load_previous_gwfparams, only_good)
    % This function reads the probe geometry in channel map and outputs the
    % spike means and SEM organized in space. If filter_300hz==0, it will
    % search for the 300hz bandpass filtered file. Otherwise, it will filter
    % again
    % Adapted parts from Cortexlab repository to read waveforms
    % By M Macedo-Lima, November 2020
    
    % KNOWN BUG:
    %   It's not perfect. If waveforms are too large, the scaling factor
    %   clobbers them together. Low priority fix right now...

    % Select folders to run
    %Prompt user to select folder
    datafolders_names = uigetfile_n_dir(root_path,'Select data directory');
    datafolders = {};
    for dummy_idx=1:length(datafolders_names)
        [~, datafolders{end+1}, ~] = fileparts(datafolders_names{dummy_idx});
    end


    %For each data folder...
    for folder_idx = 1:numel(datafolders)
        clear ops rez
        close all
        
        cur_path.name = datafolders{folder_idx};
        cur_bin_path = fullfile(root_path, cur_path.name);
        cur_ks_path = fullfile(cur_bin_path, 'kilosort4');
        cur_wfinfo_path = fullfile(cur_ks_path, 'Waveforms info');

        fprintf('Plotting autocorrelograms for %s\n', cur_bin_path)

        %Load in configuration file (contains ops struct)
        % Catch error if -mat file is not found and skip folder
        try
            load(fullfile(cur_bin_path, 'config.mat'));
            readNPY(fullfile(cur_ks_path, 'spike_times.npy'));
        catch ME
            if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
                fprintf('\nFile not found\n')
                continue
            else
                fprintf(ME.identifier)  % file not found has no identifier?? C'mon MatLab...
                fprintf(ME.message)
                continue  % Continue here instead of break because I don't know how to catch 'file not found' exception; maybe using ME.message?
            end
        end

        %Start timer
        t0 = tic;
        
        %% Define I/O and waveform parameters
        
        % Define output name for cluster;
        split_dir = split(cur_bin_path, filesep); 
    
        % DEPRECATED
        % subj_id = split(split_dir{end-1}, '-');
        % subj_id = join(subj_id(1:3), '-'); 
        % subj_id = subj_id{1}; 
    
        % Grab subject name from ePsych metadata
        subj_id = ops.epsych_metadata{1}.Name;  
    
        recording_id = split_dir{end};
        prename = strcat(subj_id, '_', recording_id);  % this is what goes into the .txt file name

        if load_previous_gwfparams
            [wf, gwfparams] = try_load_previous_gwfparams(cur_bin_path, only_good);
        else
            fprintf('Running wf extraction...\n')
            [wf, gwfparams] = get_waveforms_from_folder(cur_bin_path, only_good);
            % Save gwfparams and wf for future use
            fprintf('Saving gwfparams and wf structs to mat file\n')
            save(fullfile(cur_ks_path, 'extracted_wfs.mat'), 'gwfparams', 'wf', '-v7.3');
        end

        cluster_idx = wf.unitIDs; % store their Phy IDs

        % Delete old plots in folder
        old_files = dir(fullfile(cur_wfinfo_path, '*autocorrelogram*pdf'));
        for dummy_idx=1:numel(old_files)
            delete(fullfile(old_files(dummy_idx).folder, old_files(dummy_idx).name));
        end
        
        edges = 0:.001:.02;
        
        %% Plot
        for wf_idx=1:length(cluster_idx)
            if show_plots
                figure('Name', prename);
            else
                figure('Name', prename, 'visible', 'off');
            end
            
            cluster_phy_id = cluster_idx(wf_idx);
            
            spiketimes = double(wf.allSpikeTimePoints{wf_idx}) / gwfparams.sr;
            
            % Requires compiling relativeHist.c once first, i.e. mex relativeHist.c
            acg = relativeHist(spiketimes, spiketimes, edges);
            
            bar([-flipud(edges(2:end)'); edges(1:end-1)'], [flipud(acg); acg], 'FaceColor', 'k', 'EdgeColor', 'k');
            
            ylabel('Spikes');
            xlabel('Time (s)')
                    axis tight
%             set(gcf, 'Position',[100, 100, 800, 500])
            set(gca,'box','off')

           print(strcat(cur_wfinfo_path, filesep, prename, '_autocorrelogram', ...
               '_cluster', num2str(cluster_phy_id)), '-dpdf', '-bestfit', '-painters');
        end
        fprintf('\tDONE!\n\n')
    end
end
