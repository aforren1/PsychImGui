function test_helpers()
% TEST_HELPERS  The four convenience helpers, without Psychtoolbox.
%
%   PsychImGuiOpen, PsychImGuiFrame, PsychImGuiClose, and PsychImGuiGL exist so
%   a script never writes a Screen('BeginOpenGL') and Screen('EndOpenGL') pair
%   itself. What they have to get right is the wrapping: enter the region once,
%   leave it exactly once, leave it even when the wrapped call fails, and skip
%   the wrapping when a frame has already opened the region.
%
%   None of that needs a GPU. The test puts recording stubs for Screen and the
%   input functions on the path ahead of the real ones, runs the helpers with
%   opts.renderer = 'none', and checks the sequence of Screen calls the helpers
%   made. tests/gl/test_gl_render covers the same helpers against a real
%   window.

    % run_tests puts the stub folder on the path before the MEX is loaded and
    % takes it off after the last test. This file changes nothing on the path
    % and never calls rehash: a path change while a locked MEX is loaded sends
    % Octave 10.1 on Linux into endless recursion. See SPEC.md 14.6.
    if ~tf_screen('active')
        t_ok('the Screen stub is on the path (run this file through run_tests)', false);
        return;
    end
    t_ok('the Screen stub shadows the real Screen', true);

    % The input stubs of tf_screen provide the keyboard queue. The warning
    % stays off in case a real PsychHID answers first and fails.
    ws = warning('off', 'psychimgui:NoKeyboard');
    % Without MouseIndex, Windows has no wheel source and says so once per
    % window. That is the documented default, not what these tests check.
    wsWheel = warning('off', 'psychimgui:NoWheel');

    PsychImGui('Shutdown');            % run_tests opened a context for us
    opts = struct('renderer', 'none', 'iniFile', '');

    %% ---- the 3D graphics check --------------------------------------------
    tf_screen('set3d', 0);
    t_throws('Open without InitializeMatlabOpenGL', 'psychimgui:No3DGraphics', ...
             @() PsychImGuiOpen(11, opts));
    t_ok('the refused Open started no context', ~local_is_init());
    t_eq('the refused Open touched no GL region', tf_screen('gl'), {});
    tf_screen('set3d', 1);

    t_throws('Open needs a window', 'psychimgui:Usage', @() PsychImGuiOpen());
    t_throws('Open rejects a non-struct opts', 'psychimgui:Type', ...
             @() PsychImGuiOpen(11, 'nope'));

    %% ---- Open --------------------------------------------------------------
    tf_screen('reset');
    ig = PsychImGuiOpen(11, opts);
    t_ok('Open returns a struct', isstruct(ig));
    t_eq('Open records the window', ig.win, 11);
    t_eq('Open records the rectangle', ig.rect, [0 0 640 480]);
    t_ok('Open records a time', isnumeric(ig.opened) && ig.opened > 0);
    t_ok('Open returns a queue handle', isstruct(ig.kq));
    t_ok('Open returns an empty input struct', ...
         isstruct(ig.in) && isfield(ig.in, 'mouse'));
    t_eq('Open wrapped Init in one GL region', tf_screen('gl'), ...
         {'BeginOpenGL', 'EndOpenGL'});
    t_eq('Open left 2D mode', tf_screen('mode'), 0);
    t_ok('Open initialized the MEX', local_is_init());

    %% ---- PsychImGuiGL outside a frame ---------------------------------------
    tf_screen('reset');
    v = PsychImGuiGL(ig, 'Version');
    t_ok('GL passes the return value through', isstruct(v) && isfield(v, 'imgui'));
    t_eq('GL wrapped the subcommand', tf_screen('gl'), {'BeginOpenGL', 'EndOpenGL'});
    t_eq('GL left 2D mode', tf_screen('mode'), 0);

    tf_screen('reset');
    [wm, wk, wt] = PsychImGuiGL(ig, 'WantCapture'); %#ok<ASGLU>
    t_ok('GL passes several outputs through', ...
         islogical(wm) && islogical(wk) && islogical(wt));
    t_ok('GL with several outputs still wraps once', numel(tf_screen('gl')) == 2);

    tf_screen('reset');
    PsychImGuiGL(ig, 'StyleColorsLight');
    t_eq('GL works with no output', tf_screen('gl'), {'BeginOpenGL', 'EndOpenGL'});

    tf_screen('reset');
    PsychImGuiGL(ig.win, 'StyleColorsDark');
    t_eq('GL accepts a bare window handle', tf_screen('gl'), ...
         {'BeginOpenGL', 'EndOpenGL'});

    tf_screen('reset');
    t_throws('GL reports the subcommand error', 'psychimgui:UnknownCommand', ...
             @() PsychImGuiGL(ig, 'NoSuchSubcommand'));
    t_eq('GL left the region after an error', tf_screen('gl'), ...
         {'BeginOpenGL', 'EndOpenGL'});
    t_eq('GL left 2D mode after an error', tf_screen('mode'), 0);

    t_throws('GL rejects a handle with no window', 'psychimgui:Usage', ...
             @() PsychImGuiGL(struct('a', 1), 'Version'));
    t_throws('GL needs a subcommand', 'psychimgui:Usage', @() PsychImGuiGL(ig));

    %% ---- one whole frame ----------------------------------------------------
    tf_screen('reset');
    ig = PsychImGuiFrame('Begin', ig);
    t_eq('Frame Begin entered the region once', tf_screen('gl'), {'BeginOpenGL'});
    t_eq('Frame Begin left 3D mode on', tf_screen('mode'), 1);
    t_ok('Frame Begin returns the handle', isstruct(ig) && ig.win == 11);
    t_ok('Frame Begin fills in the input', isstruct(ig.in) && ...
         isequal(size(ig.in.mouse), [1 3]));

    % Inside a frame the region is already open, and Psychtoolbox does not nest
    % it, so PsychImGuiGL must call straight through.
    tf_screen('reset');
    PsychImGuiGL(ig, 'GetFrameCount');
    t_eq('GL does not wrap inside a frame', tf_screen('gl'), {});
    t_eq('GL leaves 3D mode alone inside a frame', tf_screen('mode'), 1);

    PsychImGui('Begin', 'helpers');
    PsychImGui('Button', 'x');
    PsychImGui('End');

    tf_screen('reset');
    PsychImGuiFrame('End', ig);
    t_eq('Frame End left the region once', tf_screen('gl'), {'EndOpenGL'});
    t_eq('Frame End left 2D mode', tf_screen('mode'), 0);

    %% ---- the older two argument form ---------------------------------------
    tf_screen('reset');
    in = PsychImGuiFrame('Begin', ig.win, ig.kq);
    t_ok('the old Frame Begin returns the input struct', ...
         isstruct(in) && isfield(in, 'display'));
    t_eq('the old Frame Begin entered the region', tf_screen('gl'), {'BeginOpenGL'});
    tf_screen('reset');
    PsychImGuiFrame('End', ig.win);
    t_eq('the old Frame End left the region', tf_screen('gl'), {'EndOpenGL'});

    t_throws('Frame rejects an unknown subcommand', 'psychimgui:Usage', ...
             @() PsychImGuiFrame('Middle', ig));

    %% ---- Close --------------------------------------------------------------
    tf_screen('reset');
    PsychImGuiClose(ig);
    t_eq('Close wrapped Shutdown in one GL region', tf_screen('gl'), ...
         {'BeginOpenGL', 'EndOpenGL'});
    t_eq('Close left 2D mode', tf_screen('mode'), 0);
    t_ok('Close shut the MEX down', ~local_is_init());

    tf_screen('reset');
    PsychImGuiClose(ig);
    t_ok('Close is safe to repeat', true);
    t_ok('Close left the MEX down', ~local_is_init());

    igc = PsychImGuiClose(ig);
    t_ok('Close returns a closed handle', isstruct(igc) && isfield(igc, 'closed'));

    % The stub raises for a window it does not know, which is what Screen does
    % after Screen('Close'). Close has to survive that and still shut down.
    tf_screen('reset');
    PsychImGuiClose(struct('win', 999, 'kq', []));
    t_eq('Close skips the region when the window is gone', tf_screen('gl'), {});
    t_ok('Close survives a window that is gone', true);

    PsychImGuiClose([]);
    t_ok('Close survives an empty handle', true);

    %% ---- Frame Begin when NewFrame fails ------------------------------------
    % With the context gone, NewFrame raises inside the wrapped region. The
    % region still has to close, or the next Screen call aborts the script.
    tf_screen('reset');
    t_throws('Frame Begin reports the NewFrame error', 'psychimgui:NotInit', ...
             @() PsychImGuiFrame('Begin', ig));
    t_eq('Frame Begin left the region after an error', tf_screen('gl'), ...
         {'BeginOpenGL', 'EndOpenGL'});
    t_eq('Frame Begin left 2D mode after an error', tf_screen('mode'), 0);

    warning(wsWheel);
    warning(ws);
end

% ------------------------------------------------------------------ helpers --

function tf = local_is_init()
    % WantCapture is one of the subcommands that needs Init.
    try
        PsychImGui('WantCapture');
        tf = true;
    catch
        tf = false;
    end
end
