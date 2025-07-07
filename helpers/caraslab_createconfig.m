function caraslab_createconfig(Savedir,chanMap, badchannels, fetch_tstart_from_behav, recording_type, single_dir)
%
% This function sets configuration parameters for kilosort.
% 
% Input variables:
%   Savedir:
%       path to directory where -mat and -csv files will be saved
%
%   chanMap:
%       path to appropriate probe type's channel map
%
%   badchannels:
%       known bad/disconnected channels. These will still be sorted but will not
%       be used for CAR filter. For some mysterious reason to me, Kilosort
%       performs better when bad channels are included in the sorting
%
%   fetch_tstart_from_behav:
%       if 1, program will attempt to find a behavioral file within
%           Savedir/Info files to grab the first relevant timestamp. This
%           helps eliminate noise from when the animal is plugged in
%           outside of the booth.
%           If Aversive is in the name of the folder, the first spout onset is
%           selected; if Aversive is not in the name of the folder, the first
%           stimulus onset is selected.
%       if 0, the entire recording ([0 Inf]) will be signalded to kilosort
%
%   recording_type: Placeholder used to adjust sampling rate. Not
%       super-useful
%       'synapse' or 'intan'

%Written by ML Caras Mar 26 2019
% Patched by M Macedo-Lima 9/8/20


%% %%%%% Don't edit this; keep scrolling %%%%% %%
%C heck that channel map exists
if ~exist(chanMap,'file')
    fprintf('\nCannot find channel map!\n')
    return
end

if nargin > 5
    datafolders = {};
    [~, datafolders{end+1}, ~] = fileparts(single_dir);
else
    %Prompt user to select folders
    datafolders_names = uigetfile_n_dir(Savedir,'Select data directory');
    datafolders = {};
    for i=1:length(datafolders_names)
        [~, datafolders{end+1}, ~] = fileparts(datafolders_names{i});
    end
end
%L oad in the channel map and identify bad channels
chandata = load(chanMap);
% badchannels = chandata.chanMap(chandata.connected == 0);

% Loop through files
for i = 1:numel(datafolders)
    clear temp ops 
    
    cur_path.name = datafolders{i};
    cur_savedir = fullfile(Savedir, cur_path.name);
    matfilename = fullfile(cur_savedir, strcat(cur_path.name, '.mat'));
    infofilename = fullfile(cur_savedir, strcat(cur_path.name, '.info'));

    % Load pre-existing ops so that non-essential fields are preserved
    try
        load(fullfile(cur_savedir, 'config.mat'));
        catch ME
        if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
            fprintf('\nPre-existing config.mat not present. Creating a new one...\n')
        else
            fprintf(ME.identifier)
            fprintf(ME.message)
            continue
        end
    end
    
    % Catch error if -mat infofile is not found
    try
        temp = load(infofilename, '-mat');
        %Get the sampling rate and number of channels
        ops.fs = temp.epData.streams.RSn1.fs;
        ops.NchanTOT = numel(temp.epData.streams.RSn1.channels);    %both active and dead
    catch ME
        if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile') || strcmp(ME.identifier, 'MATLAB:nonExistentField')
%             fprintf('\n-mat file not found')  % For concatenated recordings, this will fail. So just hard-code for now
            switch recording_type
                case 'synapse'
                    ops.fs = 24414.0625;
                case 'intan'
                    ops.fs = 30000;
            end
            ops.NchanTOT = length(chandata.chanMap);
        else
            fprintf(ME.identifier)
            fprintf(ME.message)
            continue
        end
    end

    % Load ePsych metadata if it exists
    epsych_metadata_dir = dir(fullfile(cur_savedir, 'Info files', '*ePsychMetadata.mat'));
    ops.epsych_metadata = {};
    try
        for i=1:length(epsych_metadata_dir)
            epsych_metadata = fullfile(epsych_metadata_dir(i).folder, ...
                epsych_metadata_dir(i).name);
    
            temp = load(epsych_metadata);
            Info = temp.Info;

            ops.epsych_metadata{end+1} = Info;
        end
    catch ME
        fprintf('Could not load ePsych metadata. Continuing without loading it.\n')
        fprintf(ME.identifier)
        fprintf(ME.message)
    end
    
    %Save the path to the -mat data file
    ops.rawdata = matfilename;
    
    
    %% %%%%% Edit these if necessary %%%%% %%
    %% Preprocessing parameters
    if ~isfield(ops, 'trange')
        if ~fetch_tstart_from_behav
            ops.trange = [0 Inf]; % time range to sort
        else
            tstart = fetch_tstart_from_behavior(fullfile(cur_savedir, 'Info files'));
            ops.trange = [tstart Inf];
        end
    end
    
    % Kilosort 4 filters are good enough. No need to pre-filter
    ops.highpass = 1;  % filter BEFORE kilosort (1)
    ops.fshigh = 300;  % Also used by kilosort

    ops.CAR = 1;  % CAR after highpass, before kilosort (1)
     
    ops.deline = 0;  % Fails too often; use comb for now (0)
    
    ops.comb = 1;  % Comb filter before highpass (1)

    ops.ntbuff = round((0.002 * ops.fs));
    
    ops.rm_artifacts = 1;  % Remove super high amplitude events
    ops.std_threshold = 65;  % Threshold for artifact rejection (65)
    
    ops.Nchan = ops.NchanTOT - numel(badchannels);              %number of active channels
    
    % Number of samples included in each batch of data.
    % This sets the number of samples included in each batch of data to be 
    % sorted, with a default of 60000 corresponding to 2 seconds for a 
    % sampling rate of 30000. For probes with fewer channels (say, 64 or less), 
    % increasing batch_size to include more data may improve results because it 
    % allows for better drift estimation (more spikes to estimate drift from).
    ops.NT = round(ops.fs * 5);

    ops.fbinary = fullfile(cur_savedir, strcat(cur_path.name, '.dat'));
    ops.fclean = fullfile(cur_savedir, strcat(cur_path.name, '_CLEAN.dat'));
    
    %Define the channel map and associated parameters
    ops.chanMap  = chanMap;
    ops.badchannels = badchannels;
    
    %% Kilosort4 parameters
    % MAIN PARAMETERS 

    % Total number of channels in the binary file, which may be different
    %   from the number of channels containing ephys data.
    ops.ksparams.n_chan_bin = int16(ops.NchanTOT); 
    
    % Sampling frequency of probe.
    ops.ksparams.fs = ops.fs;

    % Number of samples included in each batch of data.
    % This sets the number of samples included in each batch of data to be 
    % sorted, with a default of 60000 corresponding to 2 seconds for a 
    % sampling rate of 30000. For probes with fewer channels (say, 64 or less), 
    % increasing batch_size to include more data may improve results because it 
    % allows for better drift estimation (more spikes to estimate drift from).
    ops.ksparams.batch_size = int32(ops.NT);
    
    % Number of non-overlapping blocks for drift correction 
    % (additional nblocks-1 blocks are created in the overlaps).
    % This is the number of sections the probe is divided into when performing 
    % drift correction. The default of nblocks = 1 indicates rigid registration 
    % (the same amount of drift is applied to the entire probe). 
    % If you see different amounts of drift in your data depending on depth 
    % along the probe, increasing nblocks will help get a better drift estimate. 
    % nblocks=5 can be a good choice for single-shank Neuropixels probes. 
    % For probes with fewer channels (around 64 or less) or with sparser spacing 
    % (around 50um or more between contacts), drift estimates are not likely 
    % to be accurate, so drift correction should be skipped by setting nblocks = 0.
    ops.ksparams.nblocks = int16(0);
    
    % Th_universal and Th_learned
    % These control the threshold for spike detection when applying the 
    % universal and learned templates, respectively 
    % (loosely similar to Th(1) and Th(2) in previous versions). 
    % If few spikes are detected, or if you see neurons disappearing and 
    % reappearing over time when viewing results in Phy, it may help to 
    % decrease Th_learned. To detect more units overall, it may help to 
    % reduce Th_universal. Try reducing each threshold by 1 or 2 at a time.
    
    % Spike detection threshold for universal templates.
    ops.ksparams.Th_universal = 8;  % (9)
    
    % Spike detection threshold for learned templates.
    ops.ksparams.Th_learned = 9;  % (8)
    
    % Time in seconds when data used for sorting should begin.
    ops.ksparams.tmin = ops.trange(1);
    
    % Time in seconds when data used for sorting should end.
    ops.ksparams.tmax = ops.trange(2);
    
    % EXTRA PARAMETERS
    % Number of samples per waveform. Also size of symmetric padding for filtering.
    % 2 ms + 1 bin
    ops.ksparams.nt = int16(ops.ntbuff);
    
    % Scalar shift to apply to data before all other operations. In most cases this should be left as NaN.
    ops.ksparams.shift = NaN;
    
    % Scaling factor to apply to data before all other operations. In most cases this should be left as NaN.
    ops.ksparams.scale = NaN;
    
    % If a batch contains absolute values above this number, it will be zeroed out under the assumption that a recording artifact is present.
    % ops.ksparams.artifact_threshold = Inf;
    
    % Batch stride for computing whitening matrix.
    ops.ksparams.nskip = int16(25);
    
    % Number of nearby channels used to estimate the whitening matrix.
    ops.ksparams.whitening_range = int16(32);
    
    % Critical frequency for highpass Butterworth filter applied to data.
    % TODO: tweak KS4 code to manually turn off hp filter?
    ops.ksparams.highpass_cutoff = ops.fshigh;
    
    % For drift correction, vertical bin size in microns used for 2D histogram.
    ops.ksparams.binning_depth = 5;
    
    % Approximate spatial smoothness scale in units of microns.
    ops.ksparams.sig_interp = 20;
    
    %After sorting has finished, spikes that occur within this many ms of 
    % each other, from the same unit, are assumed to be artifacts and removed. 
    % If you see otherwise good neurons with large peaks around 0ms when 
    % viewing correlograms in Phy, increasing this value can help remove those artifacts.
    % Warning!!! Do not increase this value beyond 0.5ms as it will 
    % interfere with the ACG and CCG refractory period estimations 
    % (which normally ignores the central 1ms of the correlogram).
    ops.ksparams.duplicate_spike_ms = 0.5;

    %% Save configuration file
    configfilename  = fullfile(cur_savedir,'config.mat');
    save(configfilename,'ops')
    fprintf('Saved configuration file: %s\n', configfilename)
end



