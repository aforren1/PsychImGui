function out = tf_screen(cmd, arg)
% TF_SCREEN  Install and query the recording Screen stub used by test_helpers.
%
%   tf_screen('install')           Write the stubs to a temporary folder and
%                                  put that folder first on the path. Does
%                                  nothing when they are already installed.
%   tf_screen('cleanup')           Take the folder off the path and delete it.
%                                  run_tests calls this once, after every test.
%   tf_screen('active')            True when the stub, not the real Screen,
%                                  answers.
%   tf_screen('reset')             Clear the recorded call list.
%   tf_screen('gl')                The BeginOpenGL and EndOpenGL calls since
%                                  the last reset, as a cellstr.
%   tf_screen('mode')              1 while the stub is in the userspace OpenGL
%                                  region, 0 otherwise.
%   tf_screen('set3d', v)          The value Screen('Preference',
%                                  'Enable3DGraphics') reports.
%   tf_screen('setstereo', m)      The StereoMode Screen('GetWindowInfo')
%                                  reports. The stub records every
%                                  Screen('SelectStereoDrawBuffer', win, eye)
%                                  in the 'gl' list as SelectStereoDrawBuffer0
%                                  or SelectStereoDrawBuffer1, and raises when
%                                  it comes inside an OpenGL region, as
%                                  Psychtoolbox does.
%
%   The folder also holds stubs for the Psychtoolbox input functions that
%   PsychImGuiInput calls: KbQueueCreate, KbQueueStart, KbQueueStop,
%   KbQueueRelease, KbEventAvail, KbEventGet, GetMouse, GetMouseWheel,
%   GetMouseIndices, and GetKeyboardIndices. They forward to
%   tests/tf_input_stub, which records the device arguments and lets a test
%   inject queue events. install resets that state.
%
%   The stub answers only the subcommands the PsychImGui helpers use. It
%   is written to a temporary folder rather than committed as a file, so a
%   stray path entry can never shadow the real Screen outside a test run.
%
%   Two things this deliberately does not do, because Octave 10.1 on Linux
%   crashed the interpreter during test_helpers and they are the only calls in
%   the suite that no other test makes:
%
%     * It never calls rehash. The stub files are written before their folder
%       joins the path, and both engines pick up a new path entry on their
%       own. rehash is only needed when files appear inside a folder that is
%       already on the path, which never happens here.
%     * It does not take the folder off the path in the middle of a run.
%       run_tests removes it once, after the last test and the last Shutdown.
%
%   See SPEC.md section 14.6.

    global TF_SCREEN_GL TF_SCREEN_MODE TF_SCREEN_3D TF_SCREEN_DIR %#ok<GVMIS>
    global TF_SCREEN_STEREO %#ok<GVMIS>
    out = [];
    switch cmd
        case 'install'
            if isempty(TF_SCREEN_DIR) || ~exist(TF_SCREEN_DIR, 'dir')
                TF_SCREEN_DIR = local_install();
            end
            TF_SCREEN_GL = {};
            TF_SCREEN_MODE = 0;
            TF_SCREEN_3D = 1;
            TF_SCREEN_STEREO = 0;
            tf_input_stub('reset');
            out = TF_SCREEN_DIR;
        case 'cleanup'
            local_cleanup(TF_SCREEN_DIR);
            TF_SCREEN_DIR = '';
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
        case 'setstereo'
            TF_SCREEN_STEREO = arg;
        otherwise
            error('psychimgui:Usage', 'tf_screen: unknown command "%s".', cmd);
    end
end

function dir = local_install()
    dir = fullfile(tempdir(), sprintf('psychimgui_stub_%d', round(rand() * 1e9)));
    if ~exist(dir, 'dir')
        mkdir(dir);
    end
    % Write every file first, then add the folder. A folder that joins the path
    % with its files already in place needs no cache flush in either engine.
    local_write(fullfile(dir, 'Screen.m'), local_screen_src());
    % The input functions forward to tests/tf_input_stub, which keeps the
    % queues and records the device arguments. Each forwarder has the
    % outputs of the Psychtoolbox function it replaces.
    fwd = {'KbQueueCreate', ''; 'KbQueueStart', ''; 'KbQueueStop', ''; ...
           'KbQueueRelease', ''; 'KbEventAvail', 'n'; 'KbEventGet', '[evt, n]'; ...
           'GetMouse', '[x, y, buttons]'; 'GetMouseWheel', 'w'; ...
           'GetMouseIndices', '[idx, names, infos]'; ...
           'GetKeyboardIndices', '[idx, names, infos]'};
    for i = 1:size(fwd, 1)
        local_write(fullfile(dir, [fwd{i, 1} '.m']), local_forwarder(fwd{i, 1}, fwd{i, 2}));
    end
    local_write(fullfile(dir, 'GetSecs.m'), { ...
        'function t = GetSecs()'
        '    persistent tick'
        '    if isempty(tick); tick = 0; end'
        '    tick = tick + 1;'
        '    t = 1000 + tick / 60;'
        'end'});
    addpath(dir, '-begin');
end

function lines = local_forwarder(name, outs)
    if isempty(outs)
        lines = {sprintf('function %s(varargin)', name)
                 sprintf('    tf_input_stub(''%s'', varargin{:});', name)
                 'end'};
    else
        lines = {sprintf('function %s = %s(varargin)', outs, name)
                 sprintf('    %s = tf_input_stub(''%s'', varargin{:});', outs, name)
                 'end'};
    end
end

function local_cleanup(dir)
    if isempty(dir)
        return;
    end
    try
        rmpath(dir);
    catch
    end
    try
        delete(fullfile(dir, '*.m'));
        rmdir(dir);
    catch
        % A locked file on Windows. The folder is in tempdir, so leaving it is
        % harmless; taking it off the path is what mattered.
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
    '    global TF_SCREEN_GL TF_SCREEN_MODE TF_SCREEN_3D TF_SCREEN_STEREO'
    '    if ~iscell(TF_SCREEN_GL);   TF_SCREEN_GL = {};  end'
    '    if isempty(TF_SCREEN_MODE); TF_SCREEN_MODE = 0; end'
    '    if isempty(TF_SCREEN_3D);   TF_SCREEN_3D = 1;   end'
    '    if isempty(TF_SCREEN_STEREO); TF_SCREEN_STEREO = 0; end'
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
    '            if ~isempty(varargin) && varargin{1} >= 20'
    '                varargout{1} = [0 0 64 32];'
    '            else'
    '                varargout{1} = [0 0 640 480];'
    '            end'
    '        case ''GetOpenGLTexture'''
    '            % Texture 21 is a transposed GL_TEXTURE_2D, as MakeTexture with'
    '            % specialFlags 1 makes it; 22 is a GL_TEXTURE_RECTANGLE, the PTB'
    '            % default; 23 is an upright GL_TEXTURE_2D, as an offscreen window.'
    '            tex = varargin{2};'
    '            targets = [3553 34037 3553];'
    '            v0 = [-0.02 0 0.98];'
    '            varargout{1} = 100 + tex;'
    '            varargout{2} = targets(tex - 20);'
    '            varargout{3} = 0;'
    '            varargout{4} = v0(tex - 20);'
    '        case ''BeginOpenGL'''
    '            if varargin{1} == 999'
    '                error(''Screen:noWindow'', ''Invalid window handle 999.'');'
    '            end'
    '            TF_SCREEN_GL{end+1} = ''BeginOpenGL'';'
    '            TF_SCREEN_MODE = 1;'
    '        case ''EndOpenGL'''
    '            TF_SCREEN_GL{end+1} = ''EndOpenGL'';'
    '            TF_SCREEN_MODE = 0;'
    '        case ''GetWindowInfo'''
    '            varargout{1} = struct(''StereoMode'', TF_SCREEN_STEREO);'
    '        case ''SelectStereoDrawBuffer'''
    '            if TF_SCREEN_MODE'
    '                error(''Screen:userspace'', ''SelectStereoDrawBuffer inside BeginOpenGL.'');'
    '            end'
    '            TF_SCREEN_GL{end+1} = sprintf(''SelectStereoDrawBuffer%d'', varargin{2});'
    '        case ''GetOpenGLDrawMode'''
    '            varargout{1} = 0;'
    '            varargout{2} = TF_SCREEN_MODE;'
    '        otherwise'
    '            error(''Screen:stub'', ''the Screen stub has no subcommand %s'', cmd);'
    '    end'
    'end'
    };
end
