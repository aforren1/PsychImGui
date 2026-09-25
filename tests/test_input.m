function test_input()
% TEST_INPUT  PsychImGuiInput device selection and wheel paths, on stubs.
%
%   Uses the input stubs of tf_screen and tf_input_stub. opts.InputPlatform
%   selects the Linux, Windows, or macOS path, so every path runs on any
%   machine. What the stubs cannot show is whether the real devices send
%   what the PsychHID sources say they send; SPEC.md section 6.5 lists
%   those sources.

    if ~tf_screen('active')
        t_ok('the input stubs are on the path (run this file through run_tests)', false);
        return;
    end
    % NoWheel is off so that the paths without a wheel stay quiet. The
    % checks that a warning is issued turn it on in local_poll_warn,
    % because Octave 6.4 does not record a warning that is off in lastwarn.
    ws = warning('off', 'psychimgui:NoKeyboard');
    wsWheel = warning('off', 'psychimgui:NoWheel');
    win = 11;

    %% Linux: the indices reach the queues and GetMouse
    tf_input_stub('reset');
    opts = struct('KeyboardIndex', 8, 'MouseIndex', 5, 'InputPlatform', 'linux');
    kq = PsychImGuiInput('Start', win, opts);
    t_eq('Start stores KeyboardIndex', kq.keyboardIndex, 8);
    t_eq('Start stores MouseIndex', kq.mouseIndex, 5);
    t_eq('a slave pointer is read through its master', kq.pointerIndex, 1);
    t_eq('Linux reads the wheel from button events', kq.wheel, 'buttons');
    t_eq('the wheel queue is on the mouse', kq.wheelIndex, 5);
    t_ok('the keyboard queue is active', kq.active);

    c = tf_input_stub('calls', 'KbQueueCreate');
    t_eq('two queues', numel(c), 2);
    t_eq('the keyboard queue is on KeyboardIndex', c{1}, {8});
    t_eq('the wheel queue is on MouseIndex', c{2}{1}, 5);
    keyList = c{2}{2};
    t_ok('the wheel keyList holds buttons 1 to 7 only', ...
         numel(keyList) == 256 && isequal(find(keyList), 1:7));
    t_eq('the wheel queue asks for no valuators', numel(c{2}), 2);
    s = tf_input_stub('calls', 'KbQueueStart');
    t_eq('both queues start', s, {{8}, {5}});

    %% Linux: Poll
    tf_input_stub('inject', 5, local_clicks([5 5]));
    tf_input_stub('inject', 8, struct('Keycode', {30, 30}, 'Pressed', {1, 0}, ...
                                       'CookedKey', {97, 0}, 'Time', {1, 2}));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('two clicks of button 5 are wheel -2 (down)', in.wheel, [-2 0]);
    t_eq('the keyboard rows come from the keyboard queue only', in.keys, ...
         [30 1 97 1; 30 0 0 2]);
    g = tf_input_stub('calls', 'GetMouse');
    t_eq('Poll reads the pointer by index', g{end}, {win, 1});
    a = tf_input_stub('calls', 'KbEventAvail');
    t_eq('Poll drains the keyboard by index', a{end}, {8});

    in = PsychImGuiInput('Poll', kq, win);
    t_eq('the clicks count once', in.wheel, [0 0]);

    tf_input_stub('inject', 5, local_clicks([4 6 6 7]));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('button 4 is up, 6 left, 7 right', in.wheel, [1 1]);
    ev = local_rows(in.events);
    ev = ev(ev(:, 3) == 3, :);
    t_eq('one wheel row per click', size(ev, 1), 4);
    t_eq('the wheel rows add up to in.wheel', ...
         [sum(ev(ev(:, 4) == 1, 5)), sum(ev(ev(:, 4) == 2, 5))], in.wheel);
    t_ok('wheel rows name the mouse', all(ev(:, 2) == 5));
    e = in.events;
    t_eq('in.events is an Nx1 struct array', size(e), [4 1]);
    t_eq('wheel events have kind and axis names', {e.kind; e.name}, ...
         {'wheel', 'wheel', 'wheel', 'wheel'; 'vertical', 'horizontal', 'horizontal', 'horizontal'});
    t_ok('the text fields are char', all(cellfun(@ischar, {e.kind, e.name})));

    % Buttons through the mouse queue: device times, not the poll time.
    tf_input_stub('inject', 5, struct('Keycode', {1, 1, 3}, 'Pressed', {1, 0, 1}, ...
                                      'Time', {5.5, 5.6, 5.7}));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('button rows carry the device times', local_rows(in.events), ...
         [5.5 5 2 1 1 0; 5.6 5 2 1 0 0; 5.7 5 2 3 1 0]);
    t_eq('button events name the buttons', {in.events.name}, {'left', 'left', 'right'});
    t_ok('queued buttons do not reach in.keys', isempty(in.keys));
    t_eq('queued buttons do not reach the wheel', in.wheel, [0 0]);
    t_eq('ImGui still gets GetMouse buttons', in.buttons, [0 0 0 0 0]);

    % A release, a motion event, and a side button change nothing.
    tf_input_stub('inject', 5, struct('Keycode', {5, 0, 8}, 'Pressed', {0, 0, 1}, ...
                                       'Type', {0, 1, 0}));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('releases and other events are not clicks', in.wheel, [0 0]);

    PsychImGuiInput('Stop', kq);
    r = tf_input_stub('calls', 'KbQueueRelease');
    t_eq('Stop releases both queues', r, {{8}, {5}});
    PsychImGuiInput('Stop', kq);
    t_ok('Stop is safe to repeat', true);

    %% the empty default: PTB's defaults, no mouse queue
    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux'));
    c = tf_input_stub('calls', 'KbQueueCreate');
    t_eq('no MouseIndex creates no mouse queue', numel(c), 1);
    t_eq('no KeyboardIndex keeps the default keyboard', c{1}, {[]});
    t_eq('no MouseIndex uses GetMouseWheel', kq.wheel, 'getmousewheel');
    tf_input_stub('set', 'wheel', -1);
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('the default wheel comes from GetMouseWheel', in.wheel, [-1 0]);
    w = tf_input_stub('calls', 'GetMouseWheel');
    t_eq('GetMouseWheel gets no index', w{end}, {});
    g = tf_input_stub('calls', 'GetMouse');
    t_eq('no MouseIndex keeps GetMouse(win)', g{end}, {win});
    PsychImGuiInput('Stop', kq);
    r = tf_input_stub('calls', 'KbQueueRelease');
    t_eq('Stop releases the default keyboard only', r, {{[]}});

    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'windows'));
    t_eq('Windows without MouseIndex creates no mouse queue', ...
         numel(tf_input_stub('calls', 'KbQueueCreate')), 1);
    t_eq('Windows without MouseIndex has no wheel', kq.wheel, 'none');
    t_ok('the reason says what to set', ...
         ~isempty(strfind(kq.wheelReason, 'not supported')) && ...
         ~isempty(strfind(kq.wheelReason, 'MouseIndex')));
    PsychImGuiInput('Stop', kq);

    %% polled button transitions in the default mode
    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux'));
    tf_input_stub('inject', [], struct('Keycode', 44, 'Time', 0.5, 'CookedKey', 32));
    tf_input_stub('set', 'mouse', [10 20 1 0 0]);   % PTB: left, middle, right
    in = PsychImGuiInput('Poll', kq, win);
    r = local_rows(in.events);
    t_eq('the default keyboard is device NaN', r(1, :), [0.5 NaN 1 44 1 32]);
    t_eq('a polled press has the poll time', r(2, :), [in.time NaN 2 1 1 0]);
    t_ok('a key event has a char name', ischar(in.events(1).name));
    tf_input_stub('set', 'mouse', [10 20 0 0 1]);
    in = PsychImGuiInput('Poll', kq, win);
    r = local_rows(in.events);
    t_eq('a polled change gives a release and a press', r(:, [1 4 5]), ...
         [in.time 1 0; in.time 3 1]);
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('no events is a 0x1 struct array', size(in.events), [0 1]);
    t_eq('the empty array has the fields', fieldnames(in.events), local_fields());
    t_ok('field lists work on the empty array', isempty([in.events.time]) && ...
         numel(in.events) == 0);
    tf_input_stub('set', 'mouse', [10 20 0 0 0]);
    PsychImGuiInput('Stop', kq);

    %% the event struct and PsychImGuiEvents
    in = PsychImGuiInput('Empty');
    t_eq('Empty has a 0x1 event array', size(in.events), [0 1]);
    t_eq('the event fields in order', fieldnames(in.events), local_fields());
    E = struct('time', {1; 2; 3; 4}, 'device', {7; 5; 5; 5}, ...
               'kind', {'key'; 'button'; 'wheel'; 'wheel'}, 'code', {44; 3; 1; 2}, ...
               'name', {''; 'right'; 'vertical'; 'horizontal'}, ...
               'pressed', {1; 1; -1; 1}, 'cooked', {32; 0; 0; 0});
    t_eq('filter by kind', PsychImGuiEvents('filter', E, 'wheel'), E(3:4));
    t_eq('filter by kind and code', PsychImGuiEvents('filter', E, 'wheel', 2), E(4));
    t_eq('filter by key code', PsychImGuiEvents('filter', E, 'key', 44), E(1));
    t_eq('filter keeps a column', size(PsychImGuiEvents('filter', E, [], [1 3])), [2 1]);
    R = PsychImGuiEvents('filter', E([]), 'key', 44);
    t_ok('filter of no events is empty', isempty(R) && isstruct(R));
    t_throws('filter rejects an unknown kind', 'psychimgui:Usage', ...
             @() PsychImGuiEvents('filter', E, 'touch'));
    t_throws('decode is gone', 'psychimgui:Usage', ...
             @() PsychImGuiEvents('decode', E));
    t_throws('filter rejects a matrix', 'psychimgui:Type', ...
             @() PsychImGuiEvents('filter', zeros(2, 6), 'key'));

    %% several keyboards: one queue each, events merged in time order
    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux', ...
                                              'KeyboardIndex', [7 8]));
    t_eq('KeyboardIndex keeps the array', kq.keyboardIndex, [7 8]);
    c = tf_input_stub('calls', 'KbQueueCreate');
    t_eq('one queue per keyboard', c, {{7}, {8}});
    tf_input_stub('inject', 7, struct('Keycode', {10, 11}, 'Time', {1, 3}));
    tf_input_stub('inject', 8, struct('Keycode', {20, 21}, 'Time', {2, 4}));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('interleaved keyboards merge in time order', in.keys(:, [1 4]), ...
         [10 1; 20 2; 11 3; 21 4]);
    r = local_rows(in.events);
    t_eq('key rows in time order with their devices', r(:, 1:5), ...
         [1 7 1 10 1; 2 8 1 20 1; 3 7 1 11 1; 4 8 1 21 1]);
    PsychImGuiInput('Stop', kq);
    r = tf_input_stub('calls', 'KbQueueRelease');
    t_eq('Stop releases every keyboard queue', r, {{7}, {8}});

    %% several mice: one wheel queue each, clicks added
    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux', ...
                                              'MouseIndex', [5 6]));
    t_eq('MouseIndex keeps the array', kq.mouseIndex, [5 6]);
    t_eq('both mice have a wheel queue', kq.wheelIndex, [5 6]);
    t_eq('the pointer comes from the first mouse, through its master', ...
         kq.pointerIndex, 1);
    tf_input_stub('inject', 5, local_clicks([5 5]));
    tf_input_stub('inject', 6, local_clicks([4 6]));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('clicks of two mice add up', in.wheel, [-1 1]);
    ev = local_rows(in.events);
    ev = ev(ev(:, 3) == 3, :);
    t_eq('the wheel rows of both mice add up to in.wheel', ...
         [sum(ev(ev(:, 4) == 1, 5)), sum(ev(ev(:, 4) == 2, 5))], in.wheel);
    t_eq('each wheel row names its mouse', sort(ev(:, 2))', [5 5 6 6]);
    PsychImGuiInput('Stop', kq);
    r = tf_input_stub('calls', 'KbQueueRelease');
    t_eq('Stop releases every queue', r, {{[]}, {5}, {6}});

    % One mouse with no wheel path: one warning, the other mouse still counts.
    tf_input_stub('reset');
    tf_input_stub('set', 'failCreate', 6);
    tf_input_stub('set', 'wheelError', 'Given mouse does not have a wheel.');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux', ...
                                              'MouseIndex', [5 6]));
    t_eq('only the working mouse has a wheel', kq.wheelIndex, 5);
    t_eq('the working source is named', kq.wheel, 'buttons');
    t_ok('the reason names the failed mouse', ~isempty(strfind(kq.wheelReason, 'Mouse 6')));
    tf_input_stub('inject', 5, local_clicks(4));
    [in, id1] = local_poll_warn(kq, win);
    [~, id2] = local_poll_warn(kq, win);
    t_eq('the failed mouse warns on the first Poll', id1, 'psychimgui:NoWheel');
    t_eq('and not on the second', id2, '');
    t_eq('the working mouse still scrolls', in.wheel, [1 0]);
    PsychImGuiInput('Stop', kq);

    %% the buttons, in Dear ImGui order
    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'windows'));
    tf_input_stub('set', 'mouse', [10 20 0 1 0]);   % PTB: left, middle, right
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('the PTB middle button is ImGui button 3', in.buttons, [0 0 1 0 0]);
    PsychImGuiInput('Stop', kq);
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux', 'MouseIndex', 1));
    raw = zeros(1, 9 + 32);
    raw([3 4 8]) = 1;   % right, the wheel button 4 held, back
    raw(9 + 1) = 1;     % a modifier bit, which must not count
    tf_input_stub('set', 'mouse', [10 20 raw]);
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('XInput buttons: right and back, not the wheel', in.buttons, [0 1 0 1 0]);
    PsychImGuiInput('Stop', kq);
    tf_input_stub('set', 'mouse', [10 20 0 0 0]);

    %% Windows: the wheel axis
    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'windows', 'MouseIndex', 3));
    t_eq('Windows reads the wheel from valuator 3', kq.wheel, 'valuator');
    t_eq('Windows keeps the index for GetMouse', kq.pointerIndex, 3);
    c = tf_input_stub('calls', 'KbQueueCreate');
    kl = zeros(1, 256);
    kl(1:3) = 1;
    t_eq('the Windows mouse queue asks for buttons 1 to 3 and 3 raw valuators', ...
         c{end}, {3, kl, 3, [], 4});
    tf_input_stub('inject', 3, struct('Type', {1, 1, 1, 0}, ...
                                      'Valuators', {[0 0 120], [4 -2 0], [0 0 120], []}));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('two notches of +120 are wheel +2 (up)', in.wheel, [2 0]);
    tf_input_stub('inject', 3, struct('Type', 1, 'Valuators', [0 0 -60]));
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('a half notch down is -0.5', in.wheel, [-0.5 0]);
    r = local_rows(in.events);
    t_eq('the wheel row carries the fraction', r(:, 3:5), [3 1 -0.5]);
    % DIMOUSESTATE2 numbers buttons left, right, middle; PsychHID adds 1.
    tf_input_stub('inject', 3, struct('Keycode', {2, 3}, 'Pressed', {1, 1}, ...
                                      'Time', {7, 8}));
    in = PsychImGuiInput('Poll', kq, win);
    r = local_rows(in.events);
    t_eq('DirectInput right and middle get PTB codes 3 and 2', r(:, [1 3 4]), ...
         [7 2 3; 8 2 2]);
    PsychImGuiInput('Stop', kq);

    %% macOS and fallbacks: GetMouseWheel
    tf_input_stub('reset');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'macos', 'MouseIndex', 4));
    t_eq('macOS uses GetMouseWheel', kq.wheel, 'getmousewheel');
    t_eq('macOS makes no wheel queue', numel(tf_input_stub('calls', 'KbQueueCreate')), 1);
    tf_input_stub('set', 'wheel', 3);
    in = PsychImGuiInput('Poll', kq, win);
    t_eq('GetMouseWheel reaches in.wheel', in.wheel, [3 0]);
    w = tf_input_stub('calls', 'GetMouseWheel');
    t_eq('GetMouseWheel gets MouseIndex', w{end}, {4});
    PsychImGuiInput('Stop', kq);

    tf_input_stub('reset');
    tf_input_stub('set', 'failCreate', 5);
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux', 'MouseIndex', 5));
    t_eq('a refused mouse queue falls back to GetMouseWheel', kq.wheel, 'getmousewheel');
    PsychImGuiInput('Stop', kq);


    %% no wheel at all
    tf_input_stub('reset');
    tf_input_stub('set', 'failCreate', 3);
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'windows', 'MouseIndex', 3));
    t_eq('no wheel source', kq.wheel, 'none');
    t_eq('Windows never calls GetMouseWheel', ...
         numel(tf_input_stub('calls', 'GetMouseWheel')), 0);
    t_ok('the reason names both failures', ...
         ~isempty(strfind(kq.wheelReason, 'KbQueueCreate')) && ...
         ~isempty(strfind(kq.wheelReason, 'not supported')));
    [in, id1] = local_poll_warn(kq, win);
    [in2, id2] = local_poll_warn(kq, win);
    t_eq('the first Poll warns', id1, 'psychimgui:NoWheel');
    t_eq('the second Poll does not', id2, '');
    t_ok('Poll reports zero wheel', isequal(in.wheel, [0 0]) && isequal(in2.wheel, [0 0]));
    PsychImGuiInput('Stop', kq);

    tf_input_stub('reset');
    tf_input_stub('set', 'failCreate', 5);
    tf_input_stub('set', 'wheelError', 'Given mouse does not have a wheel.');
    kq = PsychImGuiInput('Start', win, struct('InputPlatform', 'linux', 'MouseIndex', 5));
    t_eq('Linux with no queue and no GetMouseWheel has no wheel', kq.wheel, 'none');
    t_ok('the reason quotes GetMouseWheel', ...
         ~isempty(strfind(kq.wheelReason, 'does not have a wheel')));
    PsychImGuiInput('Stop', kq);

    %% option checks
    t_throws('MouseIndex must be a number', 'psychimgui:Type', ...
             @() PsychImGuiInput('Start', win, struct('MouseIndex', 'mouse')));
    t_throws('KeyboardIndex must be a vector', 'psychimgui:Type', ...
             @() PsychImGuiInput('Start', win, struct('KeyboardIndex', [7 8; 9 10])));
    t_throws('a duplicate keyboard raises', 'psychimgui:Type', ...
             @() PsychImGuiInput('Start', win, struct('KeyboardIndex', [7 8 7])));
    t_throws('a duplicate mouse raises', 'psychimgui:Type', ...
             @() PsychImGuiInput('Start', win, struct('MouseIndex', [5 5])));
    t_throws('a device in both fields raises', 'psychimgui:Type', ...
             @() PsychImGuiInput('Start', win, struct('KeyboardIndex', 5, ...
                                                      'MouseIndex', [6 5])));

    %% Devices
    tf_input_stub('reset');
    devs = local_devices_quiet(struct('InputPlatform', 'linux'));
    fields = {'index'; 'product'; 'type'; 'xinputName'; 'xinputId'; 'isDefault'};
    t_ok('Devices returns keyboards and mice', ...
         isstruct(devs) && isfield(devs, 'keyboards') && isfield(devs, 'mice'));
    t_eq('a keyboard entry has the documented fields', fieldnames(devs.keyboards), fields);
    t_eq('a mouse entry has the documented fields', fieldnames(devs.mice), fields);
    t_eq('every mouse is listed', [devs.mice.index], [1 5 6]);
    t_eq('every keyboard is listed', [devs.keyboards.index], [7 8]);
    t_eq('Linux lists the XInput ids', [devs.mice.xinputId], [2 11 12]);
    t_eq('Linux lists the XInput names', devs.mice(2).xinputName, ...
         'Logitech USB Optical Mouse');
    t_eq('no mouse is a default', [devs.mice.isDefault], [false false false]);
    t_ok('the text fields are char', ischar(devs.mice(1).product) && ...
         ischar(devs.mice(1).type) && ischar(devs.keyboards(1).xinputName));
    devs = local_devices_quiet(struct('InputPlatform', 'windows'));
    t_ok('other systems have no XInput name', isempty(devs.mice(1).xinputName) && ...
         isnan(devs.mice(1).xinputId));

    %% PsychImGuiOpen passes the indices on
    PsychImGui('Shutdown', 'all');
    tf_input_stub('reset');
    o = struct('renderer', 'none', 'iniFile', '', 'KeyboardIndex', 7, ...
               'MouseIndex', 6, 'InputPlatform', 'linux');
    ig = PsychImGuiOpen(win, o);
    t_eq('Open passes KeyboardIndex to the queue', ig.kq.keyboardIndex, 7);
    t_eq('Open passes MouseIndex to the wheel', ig.kq.wheelIndex, 6);
    tf_input_stub('inject', 6, local_clicks(5));
    ig = PsychImGuiFrame('Begin', ig);
    t_eq('Frame Begin carries the wheel', ig.in.wheel, [-1 0]);
    PsychImGuiFrame('End', ig);
    PsychImGuiClose(ig);
    r = tf_input_stub('calls', 'KbQueueRelease');
    t_eq('Close releases both queues', r, {{7}, {6}});

    warning(wsWheel);
    warning(ws);
end

function [in, id] = local_poll_warn(kq, win)
    % One Poll with psychimgui:NoWheel on, and the id of the last warning
    % it issued, or ''. The warning prints in the test log; that is the cost
    % of an assertion that works on Octave 6.4 too.
    st = warning('on', 'psychimgui:NoWheel');
    lastwarn('');
    try
        in = PsychImGuiInput('Poll', kq, win);
    catch err
        warning(st);
        rethrow(err);
    end
    [~, id] = lastwarn();
    warning(st);
end

function devs = local_devices_quiet(opts)
    % Devices prints its listing. evalc keeps it out of the suite log.
    devs = [];
    evalc('devs = PsychImGuiInput(''Devices'', opts);');
end

function f = local_fields()
    f = {'time'; 'device'; 'kind'; 'code'; 'name'; 'pressed'; 'cooked'};
end

function r = local_rows(e)
    % The events as rows [time device kind code pressed cooked], kind 1 key,
    % 2 button, 3 wheel, so one t_eq compares several events.
    kinds = {'key', 'button', 'wheel'};
    r = zeros(numel(e), 6);
    for i = 1:numel(e)
        r(i, :) = [e(i).time, e(i).device, find(strcmp(kinds, e(i).kind)), ...
                   e(i).code, e(i).pressed, e(i).cooked];
    end
end

function evts = local_clicks(buttons)
    % One wheel click is a press and a release of its button.
    n = numel(buttons);
    evts = struct('Type', num2cell(zeros(1, 2 * n)), ...
                  'Keycode', num2cell(reshape([buttons; buttons], 1, [])), ...
                  'Pressed', num2cell(repmat([1 0], 1, n)));
end
