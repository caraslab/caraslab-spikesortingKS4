function handle_synapse_data(recnode_path, datafilename, infofilename)
    epData = TDTbin2mat(recnode_path,'TYPE',{'epocs','streams'});
    
    %Save a -mat file with the raw streams

    fprintf('\nSaving raw stream...')
    
    if ~isempty(epData.streams)
        % TODO: Using a second data streaming device wil change RSn1 to
        % RSn2. Gotta make this universal
        rawsig = epData.streams.RSn1.data; % rows = chs, cols = samples; Kilosort  likes it like this
        save(datafilename, 'rawsig','-v7.3')
    else
        fprintf('\nNo raw stream found in folder. Skipping...')
        return
    end
    
    %Remove the data from the epData structure
    % Keep in mind big recordings might crash Matlab; this helps but
    % it is still possible
    epData.streams.RSn1.data = [];
    clear rawsig
    
    fprintf('\nSaving supporting information...\n')
    save(infofilename,'epData','-v7.3')
    
    fprintf('\nSuccessfully saved raw data to:\n\t %s',datafilename)
    fprintf('\nSuccessfully saved supporting info to:\n\t %s',infofilename)
end