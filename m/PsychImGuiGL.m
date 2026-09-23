function varargout = PsychImGuiGL(ig, subcommand, varargin)
% PsychImGuiGL  Run one PsychImGui subcommand inside the OpenGL context.
%
%   PsychImGuiGL(ig, 'Subcommand', ...)
%   [a, b] = PsychImGuiGL(ig, 'Subcommand', ...)
%
%   For a subcommand that issues OpenGL calls outside a frame, such as
%   AddFontFromFileTTF or SetGlobalScale after a display change:
%
%       idx = PsychImGuiGL(ig, 'AddFontFromFileTTF', fontPath, 18);
%
%   The call enters the userspace OpenGL context, runs the subcommand, and
%   leaves the context again, so the script never writes a
%   Screen('BeginOpenGL') and Screen('EndOpenGL') pair itself. An error inside
%   the subcommand still leaves Psychtoolbox in 2D mode.
%
%   Between PsychImGuiFrame('Begin') and PsychImGuiFrame('End') the context is
%   already active. Psychtoolbox does not nest those regions, so this function
%   asks Screen('GetOpenGLDrawMode') first and, when userspace rendering is
%   already on, calls the subcommand directly. That makes the call safe
%   anywhere, and makes it identical in cost to a plain PsychImGui call inside
%   a frame.
%
%   ig may also be a bare window handle. A handle from PsychImGuiOpen also
%   makes its PsychImGui context current first, so the subcommand acts on
%   that window's GUI.
%
%   See also PsychImGuiOpen, PsychImGuiFrame, PsychImGuiClose, PsychImGui.

    if nargin < 2
        error('psychimgui:Usage', ...
              'PsychImGuiGL(ig, ''Subcommand'', ...) needs a subcommand.');
    end
    if isstruct(ig)
        if ~isfield(ig, 'win')
            error('psychimgui:Usage', ...
                  'PsychImGuiGL: the handle has no win field. Use PsychImGuiOpen.');
        end
        win = ig.win;
    elseif isnumeric(ig) && ~isempty(ig)
        win = ig;
    else
        error('psychimgui:Usage', ...
              'PsychImGuiGL: the first argument must be a PsychImGuiOpen handle.');
    end

    varargout = cell(1, nargout);

    if local_in_gl()
        local_use(ig);
        [varargout{1:nargout}] = PsychImGui(subcommand, varargin{:});
        return;
    end

    Screen('BeginOpenGL', win);
    glGuard = onCleanup(@() local_end_gl(win));
    local_use(ig);
    [varargout{1:nargout}] = PsychImGui(subcommand, varargin{:});
    clear glGuard;
end

function local_use(ig)
    if isstruct(ig) && isfield(ig, 'ctx') && ~isempty(ig.ctx) && ig.ctx ~= 0
        PsychImGui('SetContext', ig.ctx);
    end
end

function tf = local_in_gl()
    % Screen('GetOpenGLDrawMode') returns [targetwindow, isUserspaceRendering].
    % A value above zero means Screen('BeginOpenGL') is already in effect.
    tf = false;
    try
        [~, mode] = Screen('GetOpenGLDrawMode');
        tf = mode > 0;
    catch
        % An old Screen without the subcommand, or no window at all. Treat it
        % as not rendering, so the wrapping below reports the real problem.
    end
end

function local_end_gl(win)
    try
        Screen('EndOpenGL', win);
    catch
        % Nothing useful is left to do, and raising here would hide the error
        % that brought us into the cleanup.
    end
end
