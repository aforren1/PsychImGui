function out = PsychImGuiFrame(cmd, varargin)
% PsychImGuiFrame  Start and finish one PsychImGui frame.
%
%   ig = PsychImGuiFrame('Begin', ig)
%       Reads the input devices, enters the userspace OpenGL context, and
%       starts the frame. The returned struct carries the input of this frame
%       in ig.in, which the script can read for its own key and mouse
%       decisions alongside PsychImGui('WantCapture'). ig.in.events lists
%       the key, button, and wheel events of this frame with their device
%       times, for reaction times; see PsychImGuiInput and
%       PsychImGuiEvents.
%
%   PsychImGuiFrame('End', ig)
%       Renders the frame and leaves the userspace OpenGL context. When
%       ig.stereo is true, it draws the frame into both eyes: eye 0 with
%       PsychImGui('Render') and eye 1 with PsychImGui('RenderAgain'), each
%       after Screen('SelectStereoDrawBuffer') and inside its own OpenGL
%       region. Eye 1 stays selected afterwards.
%
%   Both calls first make the handle's PsychImGui context current, so a
%   script with one handle per window never calls PsychImGui('SetContext').
%
%   Between the two calls the script issues its PsychImGui widget calls, and
%   after 'End' it calls Screen('Flip'). The script never writes a
%   Screen('BeginOpenGL') and Screen('EndOpenGL') pair itself.
%
%       ig = PsychImGuiOpen(win);
%       while running
%           ig = PsychImGuiFrame('Begin', ig);
%           if PsychImGui('Begin', 'Controls')
%               [~, gain] = PsychImGui('SliderFloat', 'Gain', gain, 0, 1);
%           end
%           PsychImGui('End');
%           PsychImGuiFrame('End', ig);
%           Screen('Flip', win);
%       end
%       PsychImGuiClose(ig);
%
%   An error between 'Begin' and 'End' leaves Psychtoolbox in the userspace
%   OpenGL context. A script that catches its own errors should call
%   PsychImGuiFrame('End', ig) or PsychImGuiClose(ig) in its cleanup.
%
%   The older form, in = PsychImGuiFrame('Begin', win, kq) with
%   PsychImGuiFrame('End', win), still works for scripts written before
%   PsychImGuiOpen existed. It returns the input struct rather than a handle.
%
%   See also PsychImGuiOpen, PsychImGuiClose, PsychImGuiGL, PsychImGui.

    switch cmd
        case 'Begin'
            out = local_begin(varargin{:});
        case 'End'
            local_end(varargin{:});
            out = [];
        otherwise
            error('psychimgui:Usage', ...
                  'PsychImGuiFrame: unknown subcommand "%s".', cmd);
    end
end

function out = local_begin(handleOrWin, kq)
    if isstruct(handleOrWin)
        ig = handleOrWin;
        legacy = false;
    else
        % Older two argument form: the caller owns win and kq itself.
        if nargin < 2
            kq = [];
        end
        ig = struct('win', handleOrWin, 'kq', kq, 'rect', [], 'in', []);
        legacy = true;
    end

    ig.in = PsychImGuiInput('Poll', ig.kq, ig.win);

    Screen('BeginOpenGL', ig.win);
    try
        local_use(ig);
        PsychImGui('NewFrame', ig.in);
    catch err
        % The frame never started, so end the region here rather than leave
        % Psychtoolbox in 3D mode for the rest of the script.
        local_end_gl(ig.win);
        rethrow(err);
    end

    if legacy
        out = ig.in;
    else
        out = ig;
    end
end

function local_end(handleOrWin)
    stereo = false;
    if isstruct(handleOrWin)
        win = handleOrWin.win;
        stereo = isfield(handleOrWin, 'stereo') && ~isempty(handleOrWin.stereo) && ...
                 handleOrWin.stereo;
    else
        win = handleOrWin;
    end
    glGuard = onCleanup(@() local_end_gl(win));
    if isstruct(handleOrWin)
        local_use(handleOrWin);
    end
    if ~stereo
        PsychImGui('Render');
        clear glGuard;
        return;
    end

    % Each eye is a separate framebuffer in Psychtoolbox's stereo modes, and
    % Screen('BeginOpenGL') binds the one Screen('SelectStereoDrawBuffer')
    % chose. Selecting an eye is a Screen call, so it has to happen outside
    % the OpenGL region. The frame is built once, by Render, and submitted
    % again for the second eye, so both eyes show the same widgets and the
    % input of the frame is applied once.
    clear glGuard;
    Screen('SelectStereoDrawBuffer', win, 0);
    Screen('BeginOpenGL', win);
    glGuard = onCleanup(@() local_end_gl(win));
    PsychImGui('Render');
    clear glGuard;
    Screen('SelectStereoDrawBuffer', win, 1);
    Screen('BeginOpenGL', win);
    glGuard = onCleanup(@() local_end_gl(win));
    PsychImGui('RenderAgain');
    clear glGuard;
end

function local_use(ig)
    % A handle from PsychImGuiOpen names its context; switch to it. The older
    % handle form has no ctx field and uses whatever context is current.
    if ~isfield(ig, 'ctx') || isempty(ig.ctx) || ig.ctx == 0
        return;
    end
    try
        PsychImGui('SetContext', ig.ctx);
    catch err
        if strcmp(err.identifier, 'psychimgui:InvalidHandle')
            error('psychimgui:NotInit', ...
                  ['The PsychImGui context of this handle was shut down. Open the ' ...
                   'window again with PsychImGuiOpen.']);
        end
        rethrow(err);
    end
end

function local_end_gl(win)
    try
        Screen('EndOpenGL', win);
    catch
        % The window may already be gone, or Psychtoolbox may already be back
        % in 2D mode. Raising here would hide the error that led to this call.
    end
end
