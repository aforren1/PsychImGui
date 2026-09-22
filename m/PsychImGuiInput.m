function out = PsychImGuiInput(cmd, varargin)
% PsychImGuiInput  Collect Psychtoolbox input for PsychImGui('NewFrame').
%
%   kq = PsychImGuiInput('Start', win)
%       Creates and starts a keyboard queue and primes GetMouseWheel. Returns
%       the queue descriptor to pass to Poll and Stop.
%
%   in = PsychImGuiInput('Poll', kq, win)
%       Returns the input struct of SPEC.md section 6.1. Drains the keyboard
%       queue, reads the mouse, the wheel, the window rectangle, and the clock.
%
%   PsychImGuiInput('Stop', kq)
%       Stops and releases the keyboard queue.
%
%   in = PsychImGuiInput('Empty', rect)
%       Returns an input struct with no events, for tests and for frames the
%       script wants to draw without reading devices.
%
%   All struct fields are double arrays, so the MEX reads them without a class
%   conversion.
%
%   See also PsychImGui, PsychImGuiFrame, PsychImGuiKeymap.

    switch cmd
        case 'Start'
            out = local_start(varargin{:});
        case 'Poll'
            out = local_poll(varargin{:});
        case 'Stop'
            local_stop(varargin{:});
            out = [];
        case 'Empty'
            out = local_empty(varargin{:});
        otherwise
            error('psychimgui:Usage', ...
                  'PsychImGuiInput: unknown subcommand "%s".', cmd);
    end
end

function kq = local_start(win) %#ok<INUSD>
    kq = struct('device', [], 'active', false);
    if ~exist('KbQueueCreate', 'file')
        return;
    end
    try
        KbQueueCreate([], [], 2);   % 2 = also record CookedKey for text input
        KbQueueStart();
        kq.active = true;
    catch e
        % The keyboard queue runs on PsychHID, which needs libusb on Windows.
        % Mouse input and rendering do not, so degrade instead of stopping.
        warning('psychimgui:NoKeyboard', ...
                ['KbQueueCreate failed (%s). The GUI runs without keyboard ' ...
                 'and text input.'], e.message);
    end
    % GetMouseWheel reports clicks since the previous call, so the first call
    % returns whatever accumulated before the experiment started. Drop it.
    if exist('GetMouseWheel', 'file')
        try
            GetMouseWheel();
        catch
            % No wheel on this setup; Poll then reports zeros.
        end
    end
end

function local_stop(kq)
    if isstruct(kq) && isfield(kq, 'active') && kq.active
        KbQueueStop();
        KbQueueRelease();
    end
end

function in = local_empty(rect)
    if nargin < 1 || isempty(rect)
        rect = [0 0 640 480];
    end
    in = struct('mouse', [0 0 0], 'buttons', [0 0 0 0 0], 'wheel', [0 0], ...
                'keys', zeros(0, 4), 'display', [rect(3) - rect(1), rect(4) - rect(2)], ...
                'time', 0, 'focus', 1, 'fbscale', 1);
end

function in = local_poll(kq, win)
    rect = Screen('Rect', win);
    in = local_empty(rect);
    in.time = GetSecs();

    [x, y, buttons] = GetMouse(win);
    nb = min(numel(buttons), 5);
    b = zeros(1, 5);
    b(1:nb) = double(buttons(1:nb));
    in.buttons = b;
    % The valid flag is 0 when the pointer sits outside the client rectangle,
    % which makes NewFrame send (-FLT_MAX, -FLT_MAX) and hover nothing.
    inside = x >= rect(1) && x < rect(3) && y >= rect(2) && y < rect(4);
    in.mouse = [x - rect(1), y - rect(2), double(inside)];

    if exist('GetMouseWheel', 'file')
        try
            in.wheel = [double(GetMouseWheel()), 0];
        catch
            in.wheel = [0 0];
        end
    end

    if isstruct(kq) && isfield(kq, 'active') && kq.active
        rows = zeros(0, 4);
        n = KbEventAvail();
        for i = 1:n
            evt = KbEventGet(-1, 0);
            if isempty(evt)
                break;
            end
            cooked = 0;
            if isfield(evt, 'CookedKey')
                cooked = double(evt.CookedKey);
            end
            rows(end + 1, :) = [double(evt.Keycode), double(evt.Pressed), ...
                                cooked, double(evt.Time)]; %#ok<AGROW>
        end
        in.keys = rows;
    end
end
