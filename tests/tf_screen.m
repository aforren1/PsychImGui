function out = tf_screen(cmd, arg)
% TF_SCREEN  Install and query the recording Screen stub used by test_helpers.
%
%   dir = tf_screen('install')     Write the stubs to a temporary folder and
%                                  put that folder first on the path.
%   tf_screen('remove', dir)       Take it off the path again and delete it.
%   tf_screen('active')            True when the stub, not the real Screen,
%                                  answers.
%   tf_screen('reset')             Clear the recorded call list.
%   tf_screen('gl')                The BeginOpenGL and EndOpenGL calls since
%                                  the last reset, as a cellstr.
%   tf_screen('mode')              1 while the stub is in the userspace OpenGL
%                                  region, 0 otherwise.
%   tf_screen('set3d', v)          The value Screen('Preference',
%                                  'Enable3DGraphics') reports.
%
%   The stub answers only the subcommands the four PsychImGui helpers use. It
%   is written to a temporary folder rather than committed as a file, so a
%   stray path entry can never shadow the real Screen outside this test.

    global TF_SCREEN_GL TF_SCREEN_MODE TF_SCREEN_3D %#ok<GVMIS>
    out = [];
    switch cmd
        case 'install'
            TF_SCREEN_GL = {};
            TF_SCREEN_MODE = 0;
            TF_SCREEN_3D = 1;
            out = local_install();
        case 'remove'
            local_remove(arg);
        case 'active'
            out = false;
            try
                out = strcmp(Screen('PsychImGuiStub'), 'stub');
            catch
                % The real Screen, or no Screen at all.
            end
        case 'reset'
            TF_SCREEN_GL = {};
        case 'gl'
            out = TF_SCREEN_GL;
            if ~iscell(out); out = {}; end
        case 'mode'
            out = TF_SCREEN_MODE;
        case 'set3d'
            TF_SCREEN_3D = arg;
        otherwise
            error('psychimgui:Usage', 'tf_screen: unknown command "%s".', cmd);
    end
end

function dir = local_install()
    dir = fullfile(tempdir(), sprintf('psychimgui_stub_%d', round(rand() * 1e9)));
    if ~exist(dir, 'dir')
        mkdir(dir);
    end
    local_write(fullfile(dir, 'Screen.m'), local_screen_src());
    local_write(fullfile(dir, 'GetMouse.m'), { ...
        'function [x, y, buttons] = GetMouse(win) %#ok<INUSD>'
        '    x = 10; y = 20; buttons = [0 0 0];'
        'end'});
    local_write(fullfile(dir, 'GetMouseWheel.m'), { ...
        'function w = GetMouseWheel(varargin)'
        '    w = 0;'
        'end'});
    local_write(fullfile(dir, 'GetSecs.m'), { ...
        'function t = GetSecs()'
        '    persistent tick'
        '    if isempty(tick); tick = 0; end'
        '    tick = tick + 1;'
        '    t = 1000 + tick / 60;'
        'end'});
    addpath(dir, '-begin');
    local_rehash();
end

function local_remove(dir)
    if nargin < 1 || isempty(dir)
        return;
    end
    try
        rmpath(dir);
    catch
    end
    local_rehash();
    try
        delete(fullfile(dir, '*.m'));
        rmdir(dir);
    catch
        % A locked file on Windows. The folder is in tempdir, so leaving it is
        % harmless; taking it off the path is what mattered.
    end
end

function local_rehash()
    try
        rehash();
    catch
        % Octave refreshes its cache on addpath; nothing to do.
    end
end

function local_write(path, lines)
    fid = fopen(path, 'w');
    if fid < 0
        error('psychimgui:Usage', 'tf_screen: cannot write the stub %s', path);
    end
    for i = 1:numel(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fclose(fid);
end

function src = local_screen_src()
    src = { ...
    'function varargout = Screen(cmd, varargin)'
    '% Recording Screen stub for test_helpers. See tests/tf_screen.m.'
    '    global TF_SCREEN_GL TF_SCREEN_MODE TF_SCREEN_3D'
    '    if ~iscell(TF_SCREEN_GL);   TF_SCREEN_GL = {};  end'
    '    if isempty(TF_SCREEN_MODE); TF_SCREEN_MODE = 0; end'
    '    if isempty(TF_SCREEN_3D);   TF_SCREEN_3D = 1;   end'
    '    varargout = {};'
    '    switch cmd'
    '        case ''PsychImGuiStub'''
    '            varargout{1} = ''stub'';'
    '        case ''Preference'''
    '            if strcmp(varargin{1}, ''Enable3DGraphics'')'
    '                varargout{1} = TF_SCREEN_3D;'
    '                if numel(varargin) > 1; TF_SCREEN_3D = varargin{2}; end'
    '            else'
    '                varargout{1} = 0;'
    '            end'
    '        case ''Rect'''
    '            varargout{1} = [0 0 640 480];'
    '        case ''BeginOpenGL'''
    '            if varargin{1} == 999'
    '                error(''Screen:noWindow'', ''Invalid window handle 999.'');'
    '            end'
    '            TF_SCREEN_GL{end+1} = ''BeginOpenGL'';'
    '            TF_SCREEN_MODE = 1;'
    '        case ''EndOpenGL'''
    '            TF_SCREEN_GL{end+1} = ''EndOpenGL'';'
    '            TF_SCREEN_MODE = 0;'
    '        case ''GetOpenGLDrawMode'''
    '            varargout{1} = 0;'
    '            varargout{2} = TF_SCREEN_MODE;'
    '        otherwise'
    '            error(''Screen:stub'', ''the Screen stub has no subcommand %s'', cmd);'
    '    end'
    'end'
    };
end
