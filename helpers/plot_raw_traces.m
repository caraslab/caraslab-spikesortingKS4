% Quick n' dirty script to output voltage recordings by channel and color
% them according to timestamps detected through unit sorting

clusters_to_plot = [774, 784];
cluster_colors = {hex2rgb('92D1C3'), hex2rgb('D78521')};  % RGB format
% cluster_colors = {rgb('black')};  % RGB format
channels_to_plot = [1, 2, 3, 5];

nChanTOT = 64;  % channels in probe

start_time =  300;  % Remember if the recording is concatenated you need to take breakpoints into account
breakpoint_seconds = 1272;  % Set this to 0 if not concatenated
start_time = start_time + breakpoint_seconds;

% Key file to shade around stimulus, e.g. optogenetic stimulation if needed
key_file_name = 'SUBJ-ID-448_SUBJ-ID-448_2022-12-16_17-54-23_Active_trialInfo.csv';

shading_color = rgb('gray');

do_shading = 1;  % Set to 0 if no stimulus shading is wanting

sr = 30000;

% Before and after time chunk
pre_chunk_s = 1;
post_chunk_s = 2;

% Before and after waveform timestamp
pre_wf_s = 0.001;
post_wf_s = 0.003;

% IO paths to find your file
save_dir = '/mnt/CL_8TB_3/Matheus/Ephys recordings/OFC-Cannula_ACx-Electrode/Sorting/SUBJ-ID-448';


%% No need to change anything below here
input_dir = uigetdir(save_dir,'Select data directory');

key_file = readtable(fullfile(input_dir, 'CSV files', key_file_name), 'Delimiter', ',');

go_trial_filter = key_file.TrialType == 0;
trial_onset_offset.Onset = key_file{go_trial_filter, 'Trial_onset'} + breakpoint_seconds;
trial_onset_offset.Offset = key_file{go_trial_filter, 'Trial_offset'} + breakpoint_seconds;

% shading_color = [245, 114, 66]/255;  % RGB amber
% shading_color = [107, 159, 198]/255; % RGB blue

% Shouldn't need to tweak anything from here down
gwfparams.cluster_quality = tdfread(fullfile(input_dir, 'cluster_info.tsv'));

gwfparams.chanMap = readNPY(fullfile(input_dir, 'channel_map.npy')); % this is important esp if you got rid of files. 

nt = ceil((post_chunk_s + pre_chunk_s) * sr);

offset_bytes = ceil((start_time - pre_chunk_s + breakpoint_seconds) * sr * 2 * nChanTOT);

%Load in configuration file (contains ops struct)
% Catch error if -mat file is not found
try
    ops = load(fullfile(input_dir, 'config.mat'));
    ops = ops.ops;
catch ME
    if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
        fprintf('\nConfig file not found\n')
    else
        fprintf(ME.identifier)
        fprintf(ME.message)
    end
end


fo = fopen(ops.fclean, 'r'); % open for reading raw data
fseek(fo, offset_bytes, 'bof');
cur_buff = fread(fo, [nChanTOT nt], '*int16');
fclose(fo);

figure
scaling_factor = 500;
for ch_idx=1:length(channels_to_plot)
    ch_to_plot = channels_to_plot(ch_idx);
    snip_to_plot = cur_buff(ch_to_plot, :);

    h = plot(1:length(snip_to_plot), (scaling_factor*ch_idx) + snip_to_plot, 'black');
    
    hold on
    
    % Color wfs
    for cluster_idx=1:length(clusters_to_plot)
        cluster = clusters_to_plot(cluster_idx);
        % Find cluster file
        cluster_filename = dir([input_dir filesep '*' int2str(cluster) '.txt']);
        cluster_timestamps = fscanf(fopen(fullfile(input_dir, cluster_filename.name), 'r'),'%f');
        relevant_timestamps = cluster_timestamps(...
                                cluster_timestamps > start_time - pre_chunk_s & ...
                                cluster_timestamps < start_time + post_chunk_s);
        cur_color = cluster_colors{cluster_idx};
        for timestamp_idx=1:length(relevant_timestamps)
            timestamp = relevant_timestamps(timestamp_idx);

            x_time_idx_start = floor((timestamp - pre_wf_s - (start_time - pre_chunk_s))*sr)+1;
            
            x_time_idx_end = x_time_idx_start + ceil((pre_wf_s + post_wf_s)*sr);
            if x_time_idx_end-1 > length(snip_to_plot)
                x_time_idx_end = length(snip_to_plot);
            end
            
            plot(x_time_idx_start:x_time_idx_end-1, scaling_factor*ch_idx+snip_to_plot(x_time_idx_start:x_time_idx_end-1), 'Color', cur_color);
        end
    end
    
    if do_shading
        % Apply shading during stims
        relevant_timestamps = [];
        relevant_timestamps.Onset = trial_onset_offset.Onset((trial_onset_offset.Onset > start_time - pre_chunk_s) & ...
                                        (trial_onset_offset.Onset < start_time + post_chunk_s),:);
        relevant_timestamps.Offset = trial_onset_offset.Offset((trial_onset_offset.Onset > start_time - pre_chunk_s) & ...
                                        (trial_onset_offset.Onset < start_time + post_chunk_s),:);
                                    
        fill_YY = [min(scaling_factor*ch_idx+snip_to_plot), max(scaling_factor*ch_idx+snip_to_plot)];

        YY = repelem(fill_YY, 1, 2);  
        for event_idx=1:height(relevant_timestamps)
            fill_XX = ([relevant_timestamps(event_idx,:).Onset relevant_timestamps(event_idx,:).Offset] - start_time + pre_chunk_s)*sr;
            XX = [fill_XX, fliplr(fill_XX)];
            f = fill(XX, YY, shading_color);
            % Choose a number between 0 (invisible) and 1 (opaque) for facealpha.  
            set(f,'facealpha',.3,'edgecolor','none')
        end
    end
    
    % Save as .wav file too for fun
%     Fs = sr;                                       % Sampling Frequency (Hz)
%     Fn = Fs/2;                                              % Nyquist Frequency (Hz)
%     Wp = 8000/Fn;                                           % Passband Frequency (Normalised)
%     Ws = 8500/Fn;                                           % Stopband Frequency (Normalised)
%     Rp =   1;                                               % Passband Ripple (dB)
%     Rs = 150;                                               % Stopband Ripple (dB)
%     [n,Ws] = cheb2ord(Wp,Ws,Rp,Rs);                         % Filter Order
%     [z,p,k] = cheby2(n,Rs,Ws,'low');                        % Filter Design
%     [soslp,glp] = zp2sos(z,p,k);                            % Convert To Second-Order-Section For Stability
%     filtered_sound = filtfilt(soslp, glp, double(snip_to_plot));
    
    audio_data = rescale(resample(double(snip_to_plot), 44100, sr), -1, 1);
    audiowrite([input_dir filesep 'SampleTrace_ch' int2str(ch_to_plot) '.wav'], audio_data, 44100)
                                
end
% Transform xticklabels from samples to time
ax = ancestor(h, 'axes');
ax.XAxis.Exponent = 0;
ax.XAxis.TickLabelFormat = '%.0f';
xtl = cell2mat(cellfun(@str2num,xticklabels,'UniformOutput',false));
xticklabels([round(xtl / sr, 2)]);
print([input_dir filesep 'SampleTrace'], '-dpdf', '-bestfit', '-painters');



