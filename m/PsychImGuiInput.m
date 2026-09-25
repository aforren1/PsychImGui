function out = PsychImGuiInput(cmd, varargin)
% PsychImGuiInput  Collect Psychtoolbox input for PsychImGui('NewFrame').
%
%   kq = PsychImGuiInput('Start', win)
%   kq = PsychImGuiInput('Start', win, opts)
%       Starts the keyboard queues and the wheel sources, and returns the
%       descriptor to pass to Poll and Stop. opts can have these fields:
%
%       KeyboardIndex  PTB device indices of keyboards, as
%                      GetKeyboardIndices returns them. Each one gets its
%                      own keyboard queue, and Poll merges their key events
%                      in time order. [] (the default) makes one queue on
%                      PTB's default keyboard.
%       MouseIndex     PTB device indices of mice, as GetMouseIndices
%                      returns them. Each one gets its own wheel source, and
%                      Poll adds their clicks. The pointer position comes
%                      from the first index only. [] (the default) keeps
%                      PTB's defaults: GetMouse(win) for the pointer, and
%                      GetMouseWheel() for the wheel where it exists.
%
%       A scalar is one device. The same index twice, or one index in both
%       fields, raises psychimgui:Type: PsychHID has one queue per device.
%       Use PsychImGuiInput('Devices') to find the indices.
%
%       On Linux, when the first MouseIndex is a slave pointer (one
%       physical mouse), the pointer position comes from the master pointer
%       that the mouse moves, because GetMouse reads a slave pointer's
%       position without the window offset.
%
%       The descriptor has the fields keyboardIndex and mouseIndex (the
%       indices as given), pointerIndex (the index given to GetMouse),
%       wheelIndex (the mice with a working wheel source), wheels (one
%       element per mouse, with the fields index, source, and reason), wheel
%       (the sources in use, joined with '+', or 'none'), and wheelReason
%       (why a mouse has no wheel). The wheel sources are:
%
%       'buttons'        a queue on the mouse; each press of X11 button 4,
%                        5, 6, or 7 is one click (Linux)
%       'valuator'       a queue on the mouse; the change of the third
%                        valuator, the DirectInput wheel axis (Windows)
%       'getmousewheel'  GetMouseWheel, with the index when one is given
%                        (macOS, Linux without MouseIndex, or when the
%                        queue cannot start)
%       'none'           no wheel source. reason says why, and Poll warns
%                        once with psychimgui:NoWheel.
%
%   in = PsychImGuiInput('Poll', kq, win)
%       Returns the input struct of SPEC.md section 6.1. Drains the keyboard
%       and wheel queues, reads the pointer, the window rectangle, and the
%       clock. It never raises for a missing wheel: that wheel adds 0.
%
%       in.events holds the device events of this poll with their times,
%       for reaction times. It is an Nx1 struct array in time order, one
%       element per event, with these fields:
%
%       time     the GetSecs time of the event from KbEventGet, or in.time
%                for an event that no queue reported (see below)
%       device   the PTB device index, NaN for the default keyboard queue
%                and for the polled mouse
%       kind     'key', 'button', or 'wheel'
%       code     key: the keycode. Button: 1 left, 2 middle, 3 right, the
%                PTB numbers; 8 back and 9 forward in polled events.
%                Wheel: 1 vertical, 2 horizontal
%       name     key: KbName(code) when Psychtoolbox is present, else ''.
%                Button: 'left', 'middle', 'right', 'back', 'forward'.
%                Wheel: 'vertical', 'horizontal'
%       pressed  1 press, 0 release. Wheel: the signed clicks of the event,
%                with the sign of in.wheel
%       cooked   the CookedKey of a key, 0 for the other kinds
%
%       With no events it is a 0x1 struct array with the same fields, so
%       [in.events.time] and numel(in.events) always work. The time of
%       each press of the space bar in this frame:
%
%           e = in.events;
%           t = [e(strcmp({e.kind}, 'key') & [e.code] == KbName('space') & ...
%                  [e.pressed] == 1).time];
%
%       Keys come from the keyboard queues. Each wheel event is one
%       element, and the pressed values of an axis add up to in.wheel. With
%       a MouseIndex on Linux or Windows, the mouse queue also records
%       buttons 1 to 3, so button events have the time of the device event.
%       Dear ImGui still gets the buttons from GetMouse. Without a mouse
%       queue (no MouseIndex, macOS, or a queue that did not start), button
%       events come from the change of the GetMouse state since the previous
%       Poll and carry the poll time, so they are only as exact as the frame
%       rate. GetMouseWheel events also carry the poll time.
%       PsychImGuiEvents('filter') selects events by kind and code.
%
%   PsychImGuiInput('Stop', kq)
%       Stops and releases every queue of kq.
%
%   devs = PsychImGuiInput('Devices')
%       Prints the keyboards and the mice with their PTB device indices and
%       returns them in devs.keyboards and devs.mice. Each element has the
%       fields index, product, type, xinputName, xinputId, and isDefault.
%       On Linux, product and xinputName are the XInput device name, as
%       "xinput list" shows it, and xinputId is the XInput device id. On
%       other systems xinputName is '' and xinputId is NaN. isDefault marks
%       the keyboard of KbQueueCreate([]). It is false for every mouse,
%       because without MouseIndex no mouse queue is made.
%
%   in = PsychImGuiInput('Empty', rect)
%       Returns an input struct with no events, for tests and for frames the
%       script wants to draw without reading devices.
%
%   All struct fields are double arrays, so the MEX reads them without a class
%   conversion. The wheel follows the Dear ImGui sign: in.wheel(1) > 0
%   scrolls up, in.wheel(2) > 0 scrolls left.
%
%   See also PsychImGui, PsychImGuiFrame, PsychImGuiKeymap, PsychImGuiOpen.

    switch cmd
        case 'Start'
            out = local_start(varargin{:});
        case 'Poll'
            out = local_poll(varargin{:});
        case 'Stop'
            local_stop(varargin{:});
            out = [];
        case 'Devices'
            out = local_devices(varargin{:});
        case 'Empty'
            out = local_empty(varargin{:});
        otherwise
            error('psychimgui:Usage', ...
                  'PsychImGuiInput: unknown subcommand "%s".', cmd);
    end
end

% ------------------------------------------------------------------- Start --

function kq = local_start(win, opts) %#ok<INUSL>
    if nargin < 2 || isempty(opts)
        opts = struct();
    end
    if ~isstruct(opts)
        error('psychimgui:Type', 'PsychImGuiInput: opts must be a struct.');
    end
    kbIdx = local_index(opts, 'KeyboardIndex');
    mIdx = local_index(opts, 'MouseIndex');
    both = intersect(kbIdx, mIdx);
    if ~isempty(both)
        error('psychimgui:Type', ...
              ['PsychImGuiInput: device %d is in both KeyboardIndex and ' ...
               'MouseIndex. PsychHID has one queue per device.'], both(1));
    end
    plat = local_platform(opts);

    persistent nextId
    if isempty(nextId)
        nextId = 0;
    end
    nextId = nextId + 1;

    ptr = [];
    if ~isempty(mIdx)
        ptr = local_pointer_index(plat, mIdx(1));
    end

    % 'device' and 'active' are the fields of the version 0.2 descriptor.
    % Scripts that kept a descriptor may read them, so they stay.
    % keyboardQueues holds the devices whose queue started, {[]} for the
    % default keyboard, so Poll and Stop never touch a queue that failed.
    kq = struct('device', kbIdx, 'active', false, ...
                'keyboardIndex', kbIdx, 'mouseIndex', mIdx, ...
                'pointerIndex', ptr, 'platform', plat, ...
                'keyboardQueues', {{}}, ...
                'wheels', struct('index', {}, 'source', {}, 'reason', {}), ...
                'wheel', 'none', 'wheelIndex', [], 'wheelReason', '', ...
                'id', nextId);

    kq = local_start_keyboards(kq);
    kq = local_start_wheels(kq);
end

function kq = local_start_keyboards(kq)
    if ~exist('KbQueueCreate', 'file')
        return;
    end
    if isempty(kq.keyboardIndex)
        devs = {[]};
    else
        devs = num2cell(kq.keyboardIndex);
    end
    for i = 1:numel(devs)
        try
            % No numValuators: CookedKey comes with every key event, and
            % valuators only add motion events, which a keyboard has none of.
            KbQueueCreate(devs{i});
            KbQueueStart(devs{i});
            kq.keyboardQueues{end + 1} = devs{i};
        catch e
            % The keyboard queue runs on PsychHID, which needs libusb on
            % Windows. Mouse input and rendering do not, so degrade instead
            % of stopping, and keep the keyboards that did start.
            warning('psychimgui:NoKeyboard', ...
                    ['KbQueueCreate on keyboard %s failed (%s). The GUI gets no ' ...
                     'key or text input from it.'], local_name(devs{i}), e.message);
        end
    end
    kq.active = ~isempty(kq.keyboardQueues);
end

function kq = local_start_wheels(kq)
    if isempty(kq.mouseIndex)
        % No MouseIndex: PTB's default only. No queue, because PTB has no
        % single default mouse device for one, and a master pointer cannot
        % be queued.
        kq.wheels(1) = local_start_getmousewheel(kq.platform, []);
    else
        for i = 1:numel(kq.mouseIndex)
            w = local_start_wheel_queue(kq.platform, kq.mouseIndex(i));
            if strcmp(w.source, 'none')
                w2 = local_start_getmousewheel(kq.platform, kq.mouseIndex(i));
                if strcmp(w2.source, 'none')
                    w2.reason = [w.reason ' ' w2.reason];
                end
                w = w2;
            end
            kq.wheels(end + 1) = w;
        end
    end

    sources = {kq.wheels.source};
    ok = ~strcmp(sources, 'none');
    if any(ok)
        kq.wheel = strjoin(unique(sources(ok)), '+');
    end
    kq.wheelIndex = [kq.wheels(ok).index];
    kq.wheelReason = strjoin({kq.wheels(~ok).reason}, ' ');
end

function w = local_start_wheel_queue(plat, dev)
    % What each system delivers through a KbQueue on a mouse, from the
    % PsychHID sources (SPEC.md section 6.5):
    %  Linux    X11 reports a wheel click as a press and release of button 4
    %           (up), 5 (down), 6 (left), or 7 (right). PsychHID selects
    %           XI_RawButtonPress for every queue and gives Keycode = X11
    %           button number. Valuators are not needed for that, and with
    %           numValuators >= 2 every pointer motion would enter the queue.
    %  Windows  DirectInput reports the wheel as the Z axis, valuator 3 with
    %           numValuators >= 3. Flag 4 makes it the change per event.
    %  macOS    KbQueueCreate rejects numValuators > 0, and the wheel is no
    %           button usage, so a queue never sees it.
    w = struct('index', dev, 'source', 'none', 'reason', '');
    if strcmp(plat, 'macos')
        w.reason = sprintf('Mouse %d: macOS keyboard queues do not report the wheel.', dev);
        return;
    end
    if ~exist('KbQueueCreate', 'file') || ~exist('KbEventGet', 'file')
        w.reason = sprintf('Mouse %d: KbQueueCreate is not on the path.', dev);
        return;
    end
    try
        % Buttons 1 to 3 are in keyList for the time stamps of in.events.
        % ImGui still gets its button state from GetMouse, so hit testing
        % sees the same pointer and buttons as before.
        keyList = zeros(1, 256);
        keyList(1:3) = 1;
        if strcmp(plat, 'linux')
            keyList(4:7) = 1;
            KbQueueCreate(dev, keyList);
            source = 'buttons';
        else
            KbQueueCreate(dev, keyList, 3, [], 4);
            source = 'valuator';
        end
        KbQueueStart(dev);
        w.source = source;
    catch e
        w.reason = sprintf('Mouse %d: KbQueueCreate failed (%s).', dev, e.message);
    end
end

function w = local_start_getmousewheel(plat, dev)
    w = struct('index', dev, 'source', 'none', 'reason', '');
    who = 'Default mouse';
    if ~isempty(dev)
        who = sprintf('Mouse %d', dev);
    end
    if strcmp(plat, 'windows')
        % GetMouseWheel.m: "MS-Windows: This function is not supported and
        % will fail with an error." With an index it would skip that check
        % and send HID reports to a DirectInput index instead.
        w.reason = sprintf('%s: GetMouseWheel is not supported on Windows.', who);
        if isempty(dev)
            w.reason = [w.reason ' Set opts.MouseIndex to read the wheel ' ...
                        'through a mouse queue.'];
        end
        return;
    end
    if ~exist('GetMouseWheel', 'file')
        w.reason = sprintf('%s: GetMouseWheel is not on the path.', who);
        return;
    end
    try
        % GetMouseWheel reports clicks since the previous call, so the first
        % call returns whatever accumulated before the experiment started.
        % Drop it. A raise here means this setup has no GetMouseWheel wheel.
        local_getmousewheel(dev);
        w.source = 'getmousewheel';
    catch e
        w.reason = sprintf('%s: GetMouseWheel failed (%s).', who, e.message);
    end
end

function w = local_getmousewheel(idx)
    if isempty(idx)
        w = GetMouseWheel();
    else
        w = GetMouseWheel(idx);
    end
end

function ptr = local_pointer_index(plat, mIdx)
    % On Linux, Screen('GetMouseHelper') reads a slave pointer's position
    % from the device's own axes, without the window offset that GetMouse
    % then assumes, and only a master pointer goes through XIQueryPointer.
    % So a slave pointer is read through the master it is attached to.
    ptr = mIdx;
    if ~strcmp(plat, 'linux') || ~exist('GetMouseIndices', 'file')
        return;
    end
    try
        [idx, ~, infos] = GetMouseIndices();
        k = find(idx == mIdx, 1);
        if isempty(k) || ~strcmp(infos{k}.usageName, 'slave pointer')
            return;
        end
        for j = 1:numel(infos)
            if strcmp(infos{j}.usageName, 'master pointer') && ...
               infos{j}.interfaceID == infos{k}.locationID
                ptr = idx(j);
                return;
            end
        end
    catch
        % Keep MouseIndex. A wrong offset beats no pointer.
    end
end

function v = local_index(opts, name)
    v = [];
    if ~isfield(opts, name) || isempty(opts.(name))
        return;
    end
    v = opts.(name);
    if ~isnumeric(v) || ~isvector(v) || ~isreal(v) || any(v < 0) || any(v ~= round(v))
        error('psychimgui:Type', ...
              'PsychImGuiInput: opts.%s must be [] or PTB device indices.', name);
    end
    v = double(v(:)');
    if numel(unique(v)) ~= numel(v)
        error('psychimgui:Type', ...
              'PsychImGuiInput: opts.%s names a device twice.', name);
    end
end

function s = local_name(dev)
    if isempty(dev)
        s = '(default)';
    else
        s = sprintf('%d', dev);
    end
end

function plat = local_platform(opts)
    % opts.InputPlatform exists for the tests, which exercise the Linux and
    % Windows paths on any machine through stubs.
    if isfield(opts, 'InputPlatform') && ~isempty(opts.InputPlatform)
        plat = opts.InputPlatform;
        if ~any(strcmp(plat, {'linux', 'windows', 'macos'}))
            error('psychimgui:Type', ...
                  'PsychImGuiInput: opts.InputPlatform must be linux, windows, or macos.');
        end
    elseif ispc()
        plat = 'windows';
    elseif ismac()
        plat = 'macos';
    else
        plat = 'linux';
    end
end

% -------------------------------------------------------------------- Stop --

function local_stop(kq)
    if ~isstruct(kq)
        return;
    end
    if isfield(kq, 'keyboardQueues')
        for i = 1:numel(kq.keyboardQueues)
            local_release(kq.keyboardQueues{i});
        end
    elseif isfield(kq, 'active') && kq.active
        local_release([]);   % a version 0.2 descriptor
    end
    if isfield(kq, 'wheels')
        for i = 1:numel(kq.wheels)
            if any(strcmp(kq.wheels(i).source, {'buttons', 'valuator'}))
                local_release(kq.wheels(i).index);
            end
        end
    end
end

function local_release(dev)
    % A second Stop, or a Stop after "clear all", finds no queue. That is
    % the state Stop wants, so it is not an error.
    try
        KbQueueStop(dev);
        KbQueueRelease(dev);
    catch
    end
end

% -------------------------------------------------------------------- Poll --

function in = local_empty(rect)
    if nargin < 1 || isempty(rect)
        rect = [0 0 640 480];
    end
    in = struct('mouse', [0 0 0], 'buttons', [0 0 0 0 0], 'wheel', [0 0], ...
                'keys', zeros(0, 4), 'display', [rect(3) - rect(1), rect(4) - rect(2)], ...
                'time', 0, 'focus', 1, 'fbscale', 1, 'events', local_events(zeros(0, 6)));
end

function in = local_poll(kq, win)
    % Events are collected as rows [time device kind code pressed cooked],
    % kind 1 key, 2 button, 3 wheel, and become one struct array at the
    % end. The MEX ignores the field.
    rect = Screen('Rect', win);
    in = local_empty(rect);
    in.time = GetSecs();

    ptr = [];
    plat = local_platform(struct());
    id = 0;
    if isstruct(kq) && isfield(kq, 'pointerIndex')
        ptr = kq.pointerIndex;
        plat = kq.platform;
        id = kq.id;
    end
    if isempty(ptr)
        [x, y, buttons] = GetMouse(win);
    else
        [x, y, buttons] = GetMouse(win, ptr);
    end
    in.buttons = local_buttons(double(buttons), plat, ~isempty(ptr));
    % The valid flag is 0 when the pointer sits outside the client rectangle,
    % which makes NewFrame send (-FLT_MAX, -FLT_MAX) and hover nothing.
    inside = x >= rect(1) && x < rect(3) && y >= rect(2) && y < rect(4);
    in.mouse = [x - rect(1), y - rect(2), double(inside)];

    [in.wheel, mouseRows, queued] = local_wheel(kq, in.time);
    if ~queued
        % No mouse queue reports buttons, so the only record is the polled
        % state. Its rows carry the poll time, not the time of the click.
        mouseRows = [mouseRows; local_transitions(id, in.buttons, in.time)];
    end

    if ~isstruct(kq)
        devs = {};
    elseif isfield(kq, 'keyboardQueues')
        devs = kq.keyboardQueues;
    elseif isfield(kq, 'active') && kq.active
        devs = {[]};   % a version 0.2 descriptor
    else
        devs = {};
    end
    keyRows = zeros(0, 6);
    for d = 1:numel(devs)
        keyRows = [keyRows; local_drain_keys(devs{d})]; %#ok<AGROW>
    end
    % Each queue is in time order on its own. Merged, the rows must be too,
    % or a Shift on one keyboard would modify the wrong key on another.
    % sortrows is stable, so equal times keep the queue order.
    keyRows = sortrows(keyRows, 1);
    in.keys = keyRows(:, [4 5 6 1]);
    in.events = local_events(sortrows([keyRows; mouseRows], 1));
end

function ev = local_events(rows)
    % One struct() call with Nx1 cell arrays, rather than a struct array
    % grown in a loop, because Poll runs every frame.
    n = size(rows, 1);
    kinds = {'key'; 'button'; 'wheel'};
    kind = cell(n, 1);
    name = cell(n, 1);
    for i = 1:n
        kind{i} = kinds{rows(i, 3)};
        name{i} = local_event_name(rows(i, 3), rows(i, 4));
    end
    ev = struct('time', num2cell(rows(:, 1)), 'device', num2cell(rows(:, 2)), ...
                'kind', kind, 'code', num2cell(rows(:, 4)), 'name', name, ...
                'pressed', num2cell(rows(:, 5)), 'cooked', num2cell(rows(:, 6)));
end

function name = local_event_name(kind, code)
    name = '';
    switch kind
        case 1
            try
                name = KbName(code);
            catch
                % Without Psychtoolbox the keycode is all there is.
            end
            if ~ischar(name)
                name = '';
            end
        case 2
            codes = [1 2 3 8 9];
            names = {'left', 'middle', 'right', 'back', 'forward'};
            k = find(codes == code, 1);
            if ~isempty(k)
                name = names{k};
            end
        case 3
            if code == 1
                name = 'vertical';
            elseif code == 2
                name = 'horizontal';
            end
    end
end

function rows = local_drain_keys(dev)
    rows = zeros(0, 6);
    d = local_dev(dev);
    n = KbEventAvail(dev);
    for i = 1:n
        evt = KbEventGet(dev, 0);
        if isempty(evt)
            break;
        end
        cooked = 0;
        if isfield(evt, 'CookedKey')
            cooked = double(evt.CookedKey);
        end
        rows(end + 1, :) = [double(evt.Time), d, 1, double(evt.Keycode), ...
                            double(evt.Pressed), cooked]; %#ok<AGROW>
    end
end

function d = local_dev(dev)
    % NaN marks the default device, which has no index of its own.
    if isempty(dev)
        d = NaN;
    else
        d = dev;
    end
end

function b = local_buttons(raw, plat, byIndex)
    % Dear ImGui numbers the buttons left, right, middle, back, forward.
    % GetMouse on Windows (PsychWindowGlue.c) and the Linux core pointer
    % query return left, middle, right. The Linux XInput query, used with a
    % device index, returns X11 buttons 1 to N and then 32 modifier bits:
    % 1 left, 2 middle, 3 right, 4 to 7 the wheel, 8 back, 9 forward. The
    % wheel buttons must not reach ImGui as back and forward. macOS returns
    % primary, secondary, tertiary, which is already the ImGui order.
    b = zeros(1, 5);
    switch plat
        case 'macos'
            src = 1:5;
        case 'linux'
            if byIndex
                src = [1 3 2 8 9];
                raw = raw(1:max(0, numel(raw) - 32));
            else
                src = [1 3 2];
            end
        otherwise
            src = [1 3 2];
    end
    for i = 1:numel(src)
        if src(i) <= numel(raw)
            b(i) = raw(src(i)) ~= 0;
        end
    end
end

function rows = local_transitions(id, b, t)
    % Button rows from the polled state: one row for each change since the
    % last Poll of this descriptor. b is in the Dear ImGui order; the rows
    % use the PTB numbers 1 left, 2 middle, 3 right, and the X11 numbers 8
    % and 9 for back and forward.
    persistent ids states
    if isempty(ids)
        ids = zeros(0, 1);
        states = zeros(0, 5);
    end
    k = find(ids == id, 1);
    if isempty(k)
        ids(end + 1, 1) = id;
        states(end + 1, :) = 0;
        k = numel(ids);
    end
    codes = [1 3 2 8 9];
    changed = find(b ~= states(k, :));
    rows = zeros(numel(changed), 6);
    for i = 1:numel(changed)
        j = changed(i);
        rows(i, :) = [t, NaN, 2, codes(j), b(j), 0];
    end
    states(k, :) = b;
end

function [w, rows, queued] = local_wheel(kq, tPoll)
    % queued is true when a mouse queue reports the buttons, so Poll
    % takes the button rows from it and not from the polled state.
    w = [0 0];
    rows = zeros(0, 6);
    queued = false;
    if ~isstruct(kq) || ~isfield(kq, 'wheels')
        % A descriptor from before 'wheels' existed, or none at all. That
        % code read GetMouseWheel() and treated any failure as no wheel.
        if exist('GetMouseWheel', 'file')
            try
                w = [double(GetMouseWheel()), 0];
            catch
            end
        end
        rows = local_poll_wheel_rows(w, NaN, tPoll);
        return;
    end
    for i = 1:numel(kq.wheels)
        src = kq.wheels(i);
        try
            switch src.source
                case 'buttons'
                    [wi, r] = local_drain_buttons(src.index);
                    queued = true;
                case 'valuator'
                    [wi, r] = local_drain_valuator(src.index);
                    queued = true;
                case 'getmousewheel'
                    wi = [double(local_getmousewheel(src.index)), 0];
                    r = local_poll_wheel_rows(wi, local_dev(src.index), tPoll);
                otherwise
                    local_warn_once(kq, src.reason);
                    continue;
            end
            w = w + wi;
            rows = [rows; r]; %#ok<AGROW>
        catch e
            % This mouse adds nothing this frame; the others still count.
            local_warn_once(kq, sprintf('Mouse %s: reading the wheel (%s) failed: %s', ...
                                        local_name(src.index), src.source, e.message));
        end
    end
end

function rows = local_poll_wheel_rows(w, dev, t)
    rows = zeros(0, 6);
    for axis = 1:2
        if w(axis) ~= 0
            rows(end + 1, :) = [t, dev, 3, axis, w(axis), 0]; %#ok<AGROW>
        end
    end
end

function [w, rows] = local_drain_buttons(dev)
    % One X11 wheel click is one press and one release. Count the presses.
    % Button 4 scrolls up and 6 scrolls left, both positive in Dear ImGui.
    % Buttons 1 to 3 are X11 left, middle, right, which are the PTB numbers.
    w = [0 0];
    rows = zeros(0, 6);
    axisOf = [0 0 0 1 1 2 2];
    stepOf = [0 0 0 1 -1 1 -1];
    for guard = 1:100000
        evt = KbEventGet(dev, 0);
        if isempty(evt)
            break;
        end
        code = evt.Keycode;
        if evt.Type ~= 0 || code < 1 || code > 7
            continue;
        end
        t = double(evt.Time);
        if code <= 3
            rows(end + 1, :) = [t, dev, 2, code, double(evt.Pressed), 0]; %#ok<AGROW>
        elseif evt.Pressed
            a = axisOf(code);
            w(a) = w(a) + stepOf(code);
            rows(end + 1, :) = [t, dev, 3, a, stepOf(code), 0]; %#ok<AGROW>
        end
    end
end

function [w, rows] = local_drain_valuator(dev)
    % DirectInput reports the wheel axis in multiples of WHEEL_DELTA, 120
    % per notch, positive away from the user, which is scroll up. A precision
    % wheel reports less than 120, and Dear ImGui takes the fraction.
    % DIMOUSESTATE2 numbers the buttons 0 left, 1 right, 2 middle, and
    % PsychHID adds 1, so Keycode 2 is right and 3 is middle. Microsoft
    % documentation, not measured here.
    w = [0 0];
    rows = zeros(0, 6);
    ptbCode = [1 3 2];
    for guard = 1:100000
        evt = KbEventGet(dev, 0);
        if isempty(evt)
            break;
        end
        t = double(evt.Time);
        if evt.Type == 1 && numel(evt.Valuators) >= 3 && evt.Valuators(3) ~= 0
            clicks = double(evt.Valuators(3)) / 120;
            w(1) = w(1) + clicks;
            rows(end + 1, :) = [t, dev, 3, 1, clicks, 0]; %#ok<AGROW>
        elseif evt.Type == 0 && evt.Keycode >= 1 && evt.Keycode <= 3
            rows(end + 1, :) = [t, dev, 2, ptbCode(evt.Keycode), ...
                                double(evt.Pressed), 0]; %#ok<AGROW>
        end
    end
end

function local_warn_once(kq, reason)
    % One warning per descriptor and reason: Poll runs every frame, and a
    % warning per frame would bury the command window.
    persistent seen
    if isempty(seen)
        seen = {};
    end
    key = sprintf('%d:%s', kq.id, reason);
    if any(strcmp(seen, key))
        return;
    end
    seen{end + 1} = key;
    warning('psychimgui:NoWheel', ...
            'PsychImGuiInput: a mouse wheel does not scroll the GUI. %s', reason);
end

% ----------------------------------------------------------------- Devices --

function devs = local_devices(opts)
    if nargin < 1 || isempty(opts)
        opts = struct();
    end
    if ~exist('GetKeyboardIndices', 'file') || ~exist('GetMouseIndices', 'file')
        error('psychimgui:NoPTB', ...
              'PsychImGuiInput(''Devices'') needs Psychtoolbox on the path.');
    end
    linux = strcmp(local_platform(opts), 'linux');

    try
        [kIdx, kNames, kInfos] = GetKeyboardIndices();
        [mIdx, mNames, mInfos] = GetMouseIndices();
    catch e
        % On Windows the usual cause is a PsychHID that cannot load
        % libusb-1.0.dll, and PTB's own message says which DLL is missing.
        error('psychimgui:NoPsychHID', ...
              'PsychImGuiInput(''Devices''): PsychHID cannot list the devices: %s', ...
              e.message);
    end
    kDefault = [];
    try
        % PsychHID reports the device of KbQueueCreate([]) for class -1.
        kDefault = PsychHID('Devices', -1);
    catch
    end
    devs.keyboards = local_device_list(kIdx, kNames, kInfos, linux, kDefault);
    devs.mice = local_device_list(mIdx, mNames, mInfos, linux, []);

    local_print('Keyboards (opts.KeyboardIndex)', devs.keyboards, linux, ...
                '(* is the keyboard used when KeyboardIndex is [])');
    local_print('Mice (opts.MouseIndex)', devs.mice, linux, '');
end

function list = local_device_list(idx, names, infos, linux, defaultIdx)
    list = struct('index', {}, 'product', {}, 'type', {}, 'xinputName', {}, ...
                  'xinputId', {}, 'isDefault', {});
    for i = 1:numel(idx)
        info = struct();
        if iscell(infos) && numel(infos) >= i && isstruct(infos{i})
            info = infos{i};
        end
        product = '';
        if iscell(names) && numel(names) >= i && ischar(names{i})
            product = names{i};
        end
        type = '';
        if isfield(info, 'usageName') && ischar(info.usageName)
            type = info.usageName;
        end
        xname = '';
        xid = NaN;
        if linux
            % Linux PsychHID fills product with the XInput device name and
            % interfaceID with the XInput device id.
            xname = product;
            if isfield(info, 'interfaceID') && ~isempty(info.interfaceID)
                xid = double(info.interfaceID);
            end
        end
        list(end + 1) = struct('index', double(idx(i)), 'product', product, ...
                               'type', type, 'xinputName', xname, 'xinputId', xid, ...
                               'isDefault', ~isempty(defaultIdx) && idx(i) == defaultIdx); %#ok<AGROW>
    end
end

function local_print(title, list, linux, note)
    fprintf('%s:\n', title);
    if isempty(list)
        fprintf('  none found\n');
        return;
    end
    for i = 1:numel(list)
        mark = ' ';
        if list(i).isDefault
            mark = '*';
        end
        if linux
            fprintf('  %s %3d  %-16s  xinput id %3d  %s\n', mark, list(i).index, ...
                    list(i).type, list(i).xinputId, list(i).xinputName);
        else
            fprintf('  %s %3d  %-16s  %s\n', mark, list(i).index, list(i).type, ...
                    list(i).product);
        end
    end
    if ~isempty(note)
        fprintf('  %s\n', note);
    end
end
