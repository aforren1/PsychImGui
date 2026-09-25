function varargout = tf_input_stub(cmd, varargin)
% TF_INPUT_STUB  The state behind the Psychtoolbox input stubs of tf_screen.
%
%   tf_screen('install') writes one-line files KbQueueCreate, KbQueueStart,
%   KbQueueStop, KbQueueRelease, KbEventAvail, KbEventGet, GetMouse,
%   GetMouseWheel, GetMouseIndices, and GetKeyboardIndices to its stub
%   folder. Each one calls this function with its own name and arguments,
%   so the whole input stub lives in one file that the tests can read.
%
%   Test commands:
%
%   tf_input_stub('reset')              Default devices, no queues, no calls.
%   c = tf_input_stub('calls', name)    The argument lists of every call to
%                                       name since the last reset, as a
%                                       cell of cells.
%   tf_input_stub('inject', dev, evts)  Append the event struct array evts
%                                       to the queue of device dev. Missing
%                                       fields get the values a real
%                                       KbEventGet gives a button press.
%   tf_input_stub('set', field, value)  Change one setting:
%       failCreate   device indices whose KbQueueCreate raises. -1 means
%                    the default device ([]).
%       wheel        the value GetMouseWheel returns.
%       wheelError   a message GetMouseWheel raises with, or ''.
%       mouse        [x y buttons...] GetMouse returns.
%       mice         {indices, names, infos} GetMouseIndices returns.
%       keyboards    {indices, names, infos} GetKeyboardIndices returns.
%
%   Device [] is recorded as -1, the value PsychHID uses for the default.
%
%   The device lists follow Linux PsychHID: master pointer 1 (XInput id 2)
%   with slave pointers 5 and 6 attached, and slave keyboards 7 and 8.
%   usageName,
%   interfaceID (the XInput id), and locationID (the XInput id of the
%   master it is attached to) come from PsychHIDEnumerateHIDInputDevices.

    global TF_INPUT %#ok<GVMIS>
    if isempty(TF_INPUT) || ~isstruct(TF_INPUT)
        TF_INPUT = local_defaults();
    end
    varargout = {};
    switch cmd
        case 'reset'
            TF_INPUT = local_defaults();
        case 'calls'
            name = varargin{1};
            out = {};
            for i = 1:size(TF_INPUT.calls, 1)
                if strcmp(TF_INPUT.calls{i, 1}, name)
                    out{end + 1} = TF_INPUT.calls{i, 2}; %#ok<AGROW>
                end
            end
            varargout{1} = out;
        case 'inject'
            k = local_queue(local_dev(varargin{1}), true);
            evts = varargin{2};
            for i = 1:numel(evts)
                TF_INPUT.queues(k).events{end + 1} = local_event(evts(i));
            end
        case 'set'
            TF_INPUT.(varargin{1}) = varargin{2};

        case 'KbQueueCreate'
            local_record(cmd, varargin);
            dev = local_dev(local_arg(varargin, 1));
            if any(TF_INPUT.failCreate == dev)
                error('PsychHID:stub', 'the stub refuses a queue on device %d', dev);
            end
            k = local_queue(dev, true);
            TF_INPUT.queues(k).events = {};
            TF_INPUT.queues(k).started = false;
        case {'KbQueueStart', 'KbQueueStop', 'KbQueueRelease'}
            local_record(cmd, varargin);
            k = local_queue(local_dev(local_arg(varargin, 1)), false);
            if isempty(k)
                error('PsychHID:stub', '%s on a device with no queue', cmd);
            end
            TF_INPUT.queues(k).started = strcmp(cmd, 'KbQueueStart');
        case 'KbEventAvail'
            local_record(cmd, varargin);
            k = local_queue(local_dev(local_arg(varargin, 1)), false);
            n = 0;
            if ~isempty(k)
                n = numel(TF_INPUT.queues(k).events);
            end
            varargout{1} = n;
        case 'KbEventGet'
            local_record(cmd, varargin);
            k = local_queue(local_dev(local_arg(varargin, 1)), false);
            if isempty(k)
                error('PsychHID:stub', 'KbEventGet on a device with no queue');
            end
            evt = [];
            if ~isempty(TF_INPUT.queues(k).events)
                evt = TF_INPUT.queues(k).events{1};
                TF_INPUT.queues(k).events(1) = [];
            end
            varargout{1} = evt;
            varargout{2} = numel(TF_INPUT.queues(k).events);
        case 'GetMouse'
            local_record(cmd, varargin);
            m = TF_INPUT.mouse;
            varargout = {m(1), m(2), m(3:end)};
        case 'GetMouseWheel'
            local_record(cmd, varargin);
            if ~isempty(TF_INPUT.wheelError)
                error('GetMouseWheel:stub', '%s', TF_INPUT.wheelError);
            end
            varargout{1} = TF_INPUT.wheel;
        case 'GetMouseIndices'
            local_record(cmd, varargin);
            varargout = local_filter(TF_INPUT.mice, local_arg(varargin, 1));
        case 'GetKeyboardIndices'
            local_record(cmd, varargin);
            varargout = TF_INPUT.keyboards;
        otherwise
            error('psychimgui:Usage', 'tf_input_stub: unknown command "%s".', cmd);
    end
end

function s = local_defaults()
    % PTB indices and XInput ids differ on purpose, so a test sees which
    % one the code uses.
    mice = {[1 5 6], {'Virtual core pointer', 'Logitech USB Optical Mouse', ...
                      'PixArt Dell MS116 USB Optical Mouse'}, ...
            {local_info('master pointer', 1, 2, 3), ...
             local_info('slave pointer', 5, 11, 2), ...
             local_info('slave pointer', 6, 12, 2)}};
    kbs = {[7 8], {'AT Translated Set 2 keyboard', 'Dell KB216 Wired Keyboard'}, ...
           {local_info('slave keyboard', 7, 9, 3), ...
            local_info('slave keyboard', 8, 10, 3)}};
    s = struct('calls', {cell(0, 2)}, ...
               'queues', struct('dev', {}, 'events', {}, 'started', {}), ...
               'failCreate', [], 'wheel', 0, 'wheelError', '', ...
               'mouse', [10 20 0 0 0], 'mice', {mice}, 'keyboards', {kbs});
end

function info = local_info(usage, index, xid, attached)
    info = struct('usageName', usage, 'index', index, 'interfaceID', xid, ...
                  'locationID', attached);
end

function out = local_filter(list, typeOnly)
    % GetMouseIndices('masterPointer') and ('slavePointer') on Linux.
    out = list;
    if isempty(typeOnly)
        return;
    end
    want = 'master pointer';
    if strcmpi(typeOnly, 'slavePointer')
        want = 'slave pointer';
    end
    keep = cellfun(@(i) strcmp(i.usageName, want), list{3});
    out = {list{1}(keep), list{2}(keep), list{3}(keep)};
end

function local_record(name, args)
    global TF_INPUT %#ok<GVMIS>
    TF_INPUT.calls(end + 1, :) = {name, args};
end

function v = local_arg(args, i)
    v = [];
    if numel(args) >= i
        v = args{i};
    end
end

function d = local_dev(v)
    if isempty(v) || v < 0
        d = -1;
    else
        d = v;
    end
end

function k = local_queue(dev, create)
    global TF_INPUT %#ok<GVMIS>
    k = [];
    for i = 1:numel(TF_INPUT.queues)
        if TF_INPUT.queues(i).dev == dev
            k = i;
            return;
        end
    end
    if create
        TF_INPUT.queues(end + 1) = struct('dev', dev, 'events', {{}}, 'started', false);
        k = numel(TF_INPUT.queues);
    end
end

function e = local_event(in)
    % The fields and defaults of PsychHIDHelpers.c, PsychHIDKbQueueGetEvent.
    e = struct('Type', 0, 'Time', 0, 'Pressed', 1, 'Keycode', 0, 'CookedKey', -1, ...
               'ButtonStates', 0, 'Motion', 0, 'X', 0, 'Y', 0, 'NormX', 0, ...
               'NormY', 0, 'Valuators', zeros(1, 0));
    f = fieldnames(in);
    for i = 1:numel(f)
        e.(f{i}) = in.(f{i});
    end
end
