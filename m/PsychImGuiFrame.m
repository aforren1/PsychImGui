function out = PsychImGuiFrame(cmd, varargin)
% PsychImGuiFrame  Start and finish one PsychImGui frame.
%
%   ig = PsychImGuiFrame('Begin', ig)
%       Reads the input devices, enters the userspace OpenGL context, and
%       starts the frame. The returned struct carries the input of this frame
%       in ig.in, which the script can read for its own key and mouse
%       decisions alongside PsychImGui('WantCapture').
%
%   PsychImGuiFrame('End', ig)
%       Renders the frame and leaves the userspace OpenGL context.
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
    if isstruct(handleOrWin)
        win = handleOrWin.win;
    else
        win = handleOrWin;
    end
    glGuard = onCleanup(@() local_end_gl(win));
    PsychImGui('Render');
    clear glGuard;
end

function local_end_gl(win)
    try
        Screen('EndOpenGL', win);
    catch
        % The window may already be gone, or Psychtoolbox may already be back
        % in 2D mode. Raising here would hide the error that led to this call.
    end
end
