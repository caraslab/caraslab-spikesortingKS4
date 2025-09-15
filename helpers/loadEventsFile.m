% MIT License
% 
% Copyright (c) 2021 Open Ephys
% 
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
% 
% The above copyright notice and this permission notice shall be included in all
% copies or substantial portions of the Software.
% 
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
% SOFTWARE.

% Caras lab reformatting
% These functions were taken from the OpenEphysRecording class and modified
% to be run outside of the class definition
% M Macedo-Lima, Sep 2025

function [timestamps, processorId, state, channel, header ] = loadEventsFile(filename, recordingIndex)
    EVENT_RECORD_SIZE = 32;  % Constant

    header = readHeader(filename);

    timestamps = memmapfile(filename, 'Writable', false, 'Offset', 1024, 'Format', 'int64');

    timestamps = timestamps.Data(1:2:end);

    data = memmapfile(filename, 'Writable', false, 'Offset', 1024);
    data = reshape(data.Data, floor(EVENT_RECORD_SIZE / 2), length(timestamps));
    
    recordingNumber = data(15,:);

    mask = recordingNumber == recordingIndex - 1;
    
    timestamps = timestamps(mask);
    processorId = data(12,mask)';
    state = data(13,mask)';
    channel = data(14,mask)';


    function header = readHeader(filename)
        NUM_HEADER_BYTES = 1024;  % Constant
        
        %Return header as a containers.Map (matlab dictionary)
        header = containers.Map();
        fr = matlab.io.datastore.DsFileReader(filename);
        rawHeader = strrep(native2unicode(read(fr, NUM_HEADER_BYTES))', 'header.', '');
        rawHeader = strsplit(rawHeader,'\n');
        for i = 1:length(rawHeader)
            keyVal = strsplit(rawHeader{i},"=");
            if length(keyVal) > 1
                key = strtrim(keyVal{1});
                value = strtrim(erase(keyVal{2},";"));
                header(key) = value;
            end
        end
    end
end
