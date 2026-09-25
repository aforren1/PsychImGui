function ig = PsychImGuiOpen(win, opts)
% PsychImGuiOpen  Attach PsychImGui to a Psychtoolbox window.
%
%   ig = PsychImGuiOpen(win)
%   ig = PsychImGuiOpen(win, opts)
%
%   Puts the MEX on the path, starts Dear ImGui inside the userspace OpenGL
%   context of window win, and starts the keyboard queue. It returns a handle
%   struct that the other three helpers take:
%
%       ig = PsychImGuiFrame('Begin', ig);
%       ...
%       PsychImGuiFrame('End', ig);
%       PsychImGuiClose(ig);
%
%   The script never writes a Screen('BeginOpenGL') and Screen('EndOpenGL')
%   pair itself. Use PsychImGuiGL for a single subcommand outside a frame.
%
%   opts is the option struct of PsychImGui('Init'). Fields: renderer
%   ('auto' by default, 'opengl3', 'opengl2', 'none' for tests),
%   glslVersion, iniFile, logFile, implot, implot3d. Init ignores the other
%   fields, which this helper reads:
%
%       stereo         true or false. Overrides the stereo mode the helper
%                      reads from the window.
%       KeyboardIndex  PTB device indices of keyboards, as
%                      GetKeyboardIndices returns them. One queue each; the
%                      key events arrive merged in time order.
%       MouseIndex     PTB device indices of mice, as GetMouseIndices
%                      returns them. One wheel source each; the clicks add
%                      up. The pointer position comes from the first one.
%
%   Each field takes one index or a vector, and no index may occur twice.
%   [] or a missing field keeps PTB's default: the default keyboard queue,
%   GetMouse(win), and GetMouseWheel(), which Windows does not support. With
%   several keyboards or mice, PTB's default is the first one it finds, which
%   is not always the one on the desk. PsychImGuiInput('Devices') lists the
%   indices:
%
%       PsychImGuiInput('Devices');
%       ig = PsychImGuiOpen(win, struct('KeyboardIndex', [9 10], 'MouseIndex', 11));
%
%   PsychImGuiInput describes how the wheel is read on each system.
%
%   Each call makes a new PsychImGui context, one per window, and makes it
%   current. With two windows, open each one; the other helpers switch to the
%   context of the handle they get, so a script never calls
%   PsychImGui('SetContext') itself:
%
%       igA = PsychImGuiOpen(winA);
%       igB = PsychImGuiOpen(winB);
%       igA = PsychImGuiFrame('Begin', igA);   % ... widgets for window A
%       PsychImGuiFrame('End', igA);
%       igB = PsychImGuiFrame('Begin', igB);   % ... widgets for window B
%       PsychImGuiFrame('End', igB);
%       Screen('Flip', winA); Screen('Flip', winB);
%
%   The handle struct has these fields:
%
%       win      the window PsychImGui draws into
%       rect     Screen('Rect', win) at the time of the call
%       kq       the input descriptor from PsychImGuiInput('Start'). It
%                holds the device indices in use: kq.keyboardIndex,
%                kq.mouseIndex, kq.pointerIndex, kq.wheelIndex, and the
%                wheel source in kq.wheel
%       opened   GetSecs at the time of the call
%       opts     the option struct that went to PsychImGui('Init')
%       in       the last input struct, filled in by PsychImGuiFrame('Begin')
%       ctx      the context handle PsychImGui('Init') returned
%       stereo   true when the window has a stereo mode, so that
%                PsychImGuiFrame('End') draws the GUI into both eyes
%
%   The window must have been opened after InitializeMatlabOpenGL, because
%   Screen('BeginOpenGL') needs 3D graphics support. This function checks that
%   first and explains what to do when it is missing, rather than letting
%   Screen fail later with a less direct message.
%
%   See also PsychImGuiFrame, PsychImGuiClose, PsychImGuiGL, PsychImGui,
%   PsychImGuiInput.

    if nargin < 1 || isempty(win)
        error('psychimgui:Usage', 'PsychImGuiOpen needs a window handle.');
    end
    if nargin < 2 || isempty(opts)
        opts = struct();
    end
    if ~isstruct(opts)
        error('psychimgui:Type', 'PsychImGuiOpen: opts must be a struct.');
    end

    PsychImGuiSetup();

    if Screen('Preference', 'Enable3DGraphics') == 0
        error('psychimgui:No3DGraphics', ...
              ['Psychtoolbox 3D graphics support is off, so ' ...
               'Screen(''BeginOpenGL'') would fail.\n' ...
               'Call InitializeMatlabOpenGL(1) before you open the window:\n' ...
               '    InitializeMatlabOpenGL(1);\n' ...
               '    [win, rect] = PsychImaging(''OpenWindow'', screenid, 0);\n' ...
               '    ig = PsychImGuiOpen(win);']);
    end

    rect = Screen('Rect', win);

    if isfield(opts, 'stereo') && ~isempty(opts.stereo)
        stereo = logical(opts.stereo);
    else
        stereo = local_stereo_mode(win) > 0;
    end

    Screen('BeginOpenGL', win);
    % onCleanup, not a plain call at the end: an error inside Init must still
    % leave Psychtoolbox in 2D mode, or the next Screen call aborts the script
    % with a message about the wrong thing.
    glGuard = onCleanup(@() local_end_gl(win));
    ctx = PsychImGui('Init', win, rect, PsychImGuiKeymap(), opts);
    clear glGuard;

    kq = PsychImGuiInput('Start', win, opts);

    ig = struct('win', win, ...
                'rect', rect, ...
                'kq', kq, ...
                'opened', local_now(), ...
                'opts', opts, ...
                'in', PsychImGuiInput('Empty', rect), ...
                'ctx', ctx, ...
                'stereo', stereo);
end

function mode = local_stereo_mode(win)
    % A stereo window needs the GUI drawn once per eye. Screen reports the
    % mode in GetWindowInfo; a Screen that cannot answer, such as the test
    % stub, means mono.
    mode = 0;
    try
        info = Screen('GetWindowInfo', win);
        if isfield(info, 'StereoMode')
            mode = info.StereoMode;
        end
    catch
    end
end

function t = local_now()
    % GetSecs is the right clock here, but this field is only a timestamp, so
    % it must not be the reason the helper fails without Psychtoolbox.
    try
        t = GetSecs();
    catch
        t = now() * 86400;
    end
end

function local_end_gl(win)
    try
        Screen('EndOpenGL', win);
    catch
        % The window may already be gone. Nothing useful is left to do, and
        % raising here would hide the error that brought us into the cleanup.
    end
end
