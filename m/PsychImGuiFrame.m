function out = PsychImGuiFrame(cmd, varargin)
% PsychImGuiFrame  Two call wrapper around the per-frame PsychImGui sequence.
%
%   in = PsychImGuiFrame('Begin', win, kq)
%       Polls input, enters the userspace OpenGL context, and starts the frame.
%       Returns the input struct, which the script can read for WantCapture
%       decisions.
%
%   PsychImGuiFrame('End', win)
%       Renders the frame and leaves the userspace OpenGL context.
%
%   Between the two calls the script issues its PsychImGui widget calls. The
%   wrapper exists for scripts that prefer two lines to the five of SPEC.md
%   section 4.2; a script that already manages BeginOpenGL itself does not need
%   it.
%
%   See also PsychImGui, PsychImGuiInput.

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

function in = local_begin(win, kq)
    if nargin < 2
        kq = [];
    end
    in = PsychImGuiInput('Poll', kq, win);
    Screen('BeginOpenGL', win);
    PsychImGui('NewFrame', in);
end

function local_end(win)
    PsychImGui('Render');
    Screen('EndOpenGL', win);
end
