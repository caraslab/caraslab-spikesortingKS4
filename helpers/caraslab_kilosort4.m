function caraslab_kilosort4(Savedir, rootH, rootPython)
%This function runs kilosort4.

% Load and prepare Python environment.
fprintf('Loading Python environment...')
try
    % Find Python version in MatLab path
    pyenv('Version', rootPython, "ExecutionMode", "OutOfProcess");
catch ME
    % if strcmp(ME.identifier, 'MATLAB:Pyenv:PythonLoadedInProcess')
    throw(ME)
end

py.sys.setdlopenflags(int32(10));        % Set RTLD_NOW and RTLD_DEEPBIND

% Load modules
py.importlib.reload(py.importlib.import_module('kilosort'));

fprintf('DONE!\n')

%Prompt user to select folder
datafolders_names = uigetfile_n_dir(Savedir,'Select data directory');
datafolders = {};
for i=1:length(datafolders_names)
    [~, datafolders{end+1}, ~] = fileparts(datafolders_names{i});
end


%For each data folder...
for i = 1:numel(datafolders)
    clear ops rez
    close all

    cur_path.name = datafolders{i};
    cur_savedir = fullfile(Savedir, cur_path.name);

    %Load in configuration file (contains ops struct)
    % Catch error if -mat file is not found and skips folder
    try
        load(fullfile(cur_savedir, 'config.mat'));
    catch ME
        if strcmp(ME.identifier, 'MATLAB:load:couldNotReadFile')
            fprintf('\n-mat file not found\n')
            continue
        else
            fprintf(ME.identifier)
            fprintf(ME.message)
            break
        end
    end

    call_kilosort(cur_savedir, ops, rootH)

end


function call_kilosort(cur_savedir, ops, rootH)
    %Start timer
    t0 = tic;
    source_file = ops.fclean;
    results_dir = fullfile(cur_savedir, 'kilosort4');
    
    fprintf('Running Kilosort on %s\n', source_file)

    % Make temp data copy into fast SSD
    temp_file = fullfile(rootH, 'temp_wh.dat'); % proc file on a fast SSD
    copy_status = copyfile(source_file, temp_file);
    if copy_status == 0
        fprintf('Copying file into fast SSD failed. Verify paths. Aborting...\n')
        return
    end

   
    % Because of variable type differences between Python and MatLab,
    % It's easier to address the ones that differ between ops and default
    run_settings = copy(py.kilosort.parameters.DEFAULT_SETTINGS);
    
    ops_settings = py.dict(ops.ksparams);
    
    % Skip the starting noise in concatenated files
    if isfield(ops, 'concat_tranges')
        ops_settings{'tmin'} = ops.concat_tranges(1);
    end

    cur_probe = py.kilosort.io.load_probe(ops.chanMap);

    settings_differences = py.kilosort.parameters.compare_settings(ops_settings);
    settings_differences = struct(settings_differences{1});
    diff_fields = fieldnames(settings_differences);
    for x=1:length(diff_fields)
        cur_field = diff_fields{x};
        cur_value = settings_differences.(cur_field);
        % Have to convert to matlab type for isnan to work properly
        value_type = py.type(cur_value);
        % NaNs return as float
        if strcmp(value_type.char, '<class ''float''>')
            if isnan(cur_value)
                run_settings{cur_field} = py.None;
                continue
            end
        end
        
        run_settings{cur_field} = cur_value;
    end
    

    % ~~~~~~ RUN KILOSORT ~~~~~~  
    fprintf('Initializing Kilosort4...\n')
    py.kilosort.run_kilosort(settings=run_settings, probe=cur_probe, ...
        filename=py.str(temp_file), bad_channels=int16(ops.badchannels-1), ...
        save_preprocessed_copy=py.bool(false),...
        do_CAR=py.bool(~ops.CAR));
    fprintf('Sorting completed!\n')

    % ~~~~~~~~~~~~~~~~~~~~~~~~~~
    
    % Kilosort bugs out when selecting a different output folder than input
    fprintf('Copying files from SSD...')
    temp_results = fullfile(rootH, 'kilosort4');
    copy_status = copyfile(temp_results, results_dir);
    if copy_status == 0
        fprintf('Copying results to destination failed for some reason...\n')
    end
    delete(temp_file)
    rmdir(temp_results, 's')

    fprintf('DONE!\n')

    % Edit params.py file to match the original file (not the temp file)
    fid = fopen(fullfile(results_dir, 'params.py'), 'rt');

    new_params = textscan(fid,'%s','delimiter','\n');
    fclose(fid);

    new_params = new_params{:,:};
    idx = contains(new_params,'dat_path') ;
    new_params(idx) = [];

    new_params{end+1} = strcat('dat_path = ''', source_file, '''');

    fid = fopen(fullfile(results_dir, 'params.py'), 'wt');

    fprintf(fid,'%s\n',new_params{:});
    fclose(fid) ;

    tEnd = toc(t0);
    fprintf('Kilosort done in: %d minutes and %f seconds\n\n', floor(tEnd/60), rem(tEnd,60));