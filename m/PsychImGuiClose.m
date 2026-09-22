function ig = PsychImGuiClose(ig)
% PsychImGuiClose  Detach PsychImGui from its Psychtoolbox window.
%
%   PsychImGuiClose(ig)
%   ig = PsychImGuiClose(ig)
%
%   Destroys the Dear ImGui context inside the userspace OpenGL context and
%   stops the keyboard queue. The MEX unlocks, so "clear mex" works again.
%
%   The call is safe to repeat, and safe after the window has closed: it
%   catches the Screen errors and still shuts the MEX down, because a MEX that
%   stays locked keeps the whole binding loaded for the rest of the session.
%   That makes it usable from an onCleanup or a catch block:
%
%       ig = PsychImGuiOpen(win);
%       guard = onCleanup(@() PsychImGuiClose(ig));
%
%   With an output argument it returns the handle with the fields that no
%   longer refer to anything cleared, so a second call has nothing left to do.
%
%   See also PsychImGuiOpen, PsychImGuiFrame, PsychImGuiGL, PsychImGui.

    win = [];
    kq = [];
    if nargin >= 1 && isstruct(ig)
        if isfield(ig, 'win'); win = ig.win; end
        if isfield(ig, 'kq');  kq = ig.kq;   end
    elseif nargin >= 1 && isnumeric(ig) && ~isempty(ig)
        win = ig;   % a bare window handle, for scripts that kept only that
    end

    inGL = false;
    if ~isempty(win)
        try
            Screen('BeginOpenGL', win);
            inGL = true;
        catch
            % The window is gone, or 3D graphics are off. Shutdown below then
            % skips deleting the GL objects and warns; Psychtoolbox frees them
            % with the context anyway.
        end
    end

    try
        PsychImGui('Shutdown');
    catch err
        if inGL
            local_end_gl(win);
            inGL = false;
        end
        if ~strcmp(err.identifier, 'psychimgui:NotBuilt')
            rethrow(err);
        end
        % The MEX was never on the path, so there is nothing to shut down.
    end

    if inGL
        local_end_gl(win);
    end

    if ~isempty(kq)
        try
            PsychImGuiInput('Stop', kq);
        catch
            % Already stopped, or PsychHID is unavailable. Either way the
            % queue is not running now, which is what this call wanted.
        end
    end

    if nargout > 0
        if ~isstruct(ig)
            ig = struct();
        end
        ig.kq = [];
        ig.closed = local_now();
    end
end

function t = local_now()
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
        % Nothing useful is left to do, and raising here would hide the error
        % that brought us into the cleanup.
    end
end
