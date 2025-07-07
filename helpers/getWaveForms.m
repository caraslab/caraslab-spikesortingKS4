function wf = getWaveForms(gwfparams)
% function wf = getWaveForms(gwfparams)
%
% Extracts individual spike waveforms from the raw datafile, for multiple
% clusters. Returns the waveforms and their means within clusters.
%
% Contributed by C. Schoonover and A. Fink
% Patched by M Macedo-Lima 10/08/20
%
% % EXAMPLE INPUT
% gwfparams.dataDir = '/path/to/data/';    % KiloSort/Phy output folder
% gwfparams.fileName = 'data.dat';         % .dat file containing the raw 
% gwfparams.dataType = 'int16';            % Data type of .dat file (this should be BP filtered)
% gwfparams.nCh = 32;                      % Number of channels that were streamed to disk in .dat file
% gwfparams.wfWin = [-40 41];              % Number of samples before and after spiketime to include in waveform
% gwfparams.nWf = 2000;                    % Number of waveforms per unit to pull out
% gwfparams.spikeTimes =    [2,3,5,7,8,9]; % Vector of cluster spike times (in samples) same length as .spikeClusters
% gwfparams.spikeClusters = [1,2,1,1,1,2]; % Vector of cluster IDs (Phy nomenclature)   same length as .spikeTimes
%
% % OUTPUT
% wf.unitIDs                               % [nClu,1]            List of cluster IDs; defines order used in all wf.* variables
% wf.spikeTimeKeeps                        % [nClu,nWf]          Which spike times were used for the waveforms
% wf.waveForms                             % [nClu,nWf,nCh,nSWf] Individual waveforms
% wf.waveFormsMean                         % [nClu,nCh,nSWf]     Average of all waveforms (per channel)
%                                          % nClu: number of different clusters in .spikeClusters
%                                          % nSWf: number of samples per waveform
%
% % USAGE
% wf = getWaveForms(gwfparams);

ops = gwfparams.ops;
temp_dir.fullfile = ops.fclean;
temp_dir_split = split(temp_dir.fullfile, filesep);
temp_dir.folder = join(temp_dir_split(1:end-1), filesep);
temp_dir.folder = temp_dir.folder{:};
temp_dir.name = temp_dir_split{end};
fileName = ops.fclean;


% Save modified ops
save(fullfile(gwfparams.rawDir, 'config.mat'), 'ops');

filenamestruct = dir(fileName);
dataTypeNBytes = numel(typecast(cast(0, gwfparams.dataType), 'uint8')); % determine number of bytes per sample
nSamp = filenamestruct.bytes/(gwfparams.nCh*dataTypeNBytes);  % Number of samples per channel
wfNSamples = length(gwfparams.wfWin(1):gwfparams.wfWin(end));
mmf = memmapfile(fileName, 'Format', {gwfparams.dataType, [gwfparams.nCh nSamp], 'x'});


chMap = readNPY(fullfile(gwfparams.dataDir, 'channel_map.npy'))+1;               % Order in which data was streamed to disk; must be 1-indexed for Matlab
nChInMap = numel(chMap);

%% phy2
unitIDs = gwfparams.good_clusters;
numUnits = size(gwfparams.good_clusters,1);
spikeTimeKeeps = nan(numUnits,gwfparams.nWf);
allSpikeTimes = cell(numUnits, 1);

%%
waveForms = nan(numUnits,gwfparams.nWf,nChInMap,wfNSamples);
waveFormsMean = nan(numUnits,nChInMap,wfNSamples);

% Added by MML to speed up measurements. Will measure only good clusters
%% phy1
% good_clusters = gwfparams.cluster_quality(strcmp(gwfparams.cluster_quality.group(:,1), 'g'),1);
% good_clusters = table2array(good_clusters);
% [ , good_cluster_idx] = intersect(unitIDs, good_clusters);
%% phy2
good_clusters = gwfparams.good_clusters;
%%

% MML edit
counter = 0;
progress_bar = waitbar(0, strcat("Completed ", int2str(counter), " units of ", int2str(length(good_clusters))), 'Name', 'Waveform extraction');
for curUnitInd=1:numUnits
    curUnitID = good_clusters(curUnitInd);
    curSpikeTimes = gwfparams.spikeTimes(gwfparams.spikeClusters==curUnitID);
    
    % Remove noisy part of this SUBJ-ID-174 recording (135 - 360 s)
%     if strfind(gwfparams.rawDir, 'SUBJ-ID-174') && strcmp(gwfparams.fileName, '201116_concat_CLEAN.dat')
%         curSpikeTimes = curSpikeTimes(curSpikeTimes < (135*gwfparams.sr) | curSpikeTimes > (360*gwfparams.sr));
%     end
    
    allSpikeTimes{curUnitInd} = curSpikeTimes;
    curUnitnSpikes = size(curSpikeTimes,1);
    if ismember(curUnitID, good_clusters)
        spikeTimesRP = curSpikeTimes(randperm(curUnitnSpikes));
        
        spikeTimeKeeps(curUnitInd,1:min([gwfparams.nWf curUnitnSpikes])) = sort(spikeTimesRP(1:min([gwfparams.nWf curUnitnSpikes])));
        for curSpikeTime = 1:min([gwfparams.nWf curUnitnSpikes])
            try
            tmpWf = mmf.Data.x(1:gwfparams.nCh, ...
                round(spikeTimeKeeps(curUnitInd,curSpikeTime)+ gwfparams.wfWin(1):...
                spikeTimeKeeps(curUnitInd,curSpikeTime)+ gwfparams.wfWin(end)));
            catch ME
                if strcmp(ME.identifier, 'MATLAB:badsubscript')
                    % This catches the error of trying to fetch the last
                    % spike in the recording that spans larger than the
                    % recording itself
                    continue
                else
                    throw(ME)
                end
            end
            waveForms(curUnitInd,curSpikeTime,:,:) = tmpWf(chMap,:);
        end
        waveFormsMean(curUnitInd,:,:) = squeeze(nanmean(waveForms(curUnitInd,:,:,:),2));
    
        % MML edit
        counter = counter + 1;
        waitbar(counter/length(good_clusters), progress_bar, ...
            strcat("Completed, ", int2str(counter), " units of ", int2str(length(good_clusters))))
    else
        continue
    end
end

close(progress_bar)

% Package in wf struct
wf.unitIDs = unitIDs;
wf.spikeTimeKeeps = spikeTimeKeeps;
wf.waveForms = waveForms;
wf.waveFormsMean = waveFormsMean;

%% MML: phy2
wf.allSpikeTimePoints = allSpikeTimes;

end