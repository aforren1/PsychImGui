function test_gl_contexts()
% TEST_GL_CONTEXTS  Two Psychtoolbox windows, one PsychImGui context each.
%
%   Needs Psychtoolbox and a GPU. run_tests does not call this file; run it by
%   hand on a developer machine:
%
%       addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
%       test_gl_contexts
%
%   Psychtoolbox gives every onscreen window its own userspace OpenGL context
%   and shares no objects between windows, so each PsychImGui context has to
%   create, use, and delete its font texture and shader in its own window's
%   context. The test draws a red panel into one window and a blue one into
%   the other, reads both back, and checks the guard that catches a call made
%   with the wrong window's context current. It also reads the GPU time the
%   timestamp queries report.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if isempty(TST_PASS); TST_PASS = 0; end
    if isempty(TST_FAIL); TST_FAIL = 0; end

    if exist('Screen', 'file') == 0
        fprintf('SKIP test_gl_contexts: Psychtoolbox is not installed.\n');
        return;
    end
    try
        Screen('Version');
    catch e
        fprintf('SKIP test_gl_contexts: Screen does not load (%s).\n', e.message);
        return;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(here));
    addpath(fullfile(root, 'm'), fullfile(root, 'tests'), here);
    PsychImGuiSetup();

    winA = [];
    winB = [];
    igA = [];
    igB = [];
    try
        [winA, ~, prefGuard] = ptb_test_window([0 0 320 240]); %#ok<ASGLU>
        [winB, ~, prefGuardB] = ptb_test_window([340 0 660 240]); %#ok<ASGLU>
        igA = PsychImGuiOpen(winA);
        igB = PsychImGuiOpen(winB);
        t_ok('each window gets its own context', igA.ctx ~= igB.ctx);
        vA = PsychImGuiGL(igA, 'Version');
        vB = PsychImGuiGL(igB, 'Version');
        t_eq('Version answers for the handle''s context, A', vA.context, igA.ctx);
        t_eq('Version answers for the handle''s context, B', vB.context, igB.ctx);
        fprintf('  A: %s on %s, GPU timer %d\n', vA.renderer, vA.glVersion, vA.gpuTimer);
        fprintf('  B: %s on %s, GPU timer %d\n', vB.renderer, vB.glVersion, vB.gpuTimer);

        red = [0.9 0.1 0.1 1];
        blue = [0.1 0.2 0.9 1];
        for f = 1:4
            igA = local_frame(igA, red);
            igB = local_frame(igB, blue);
            if f < 4
                Screen('Flip', winA, [], [], 1);
                Screen('Flip', winB);
            end
        end
        imgA = double(Screen('GetImage', winA, [], 'backBuffer')) / 255;
        imgB = double(Screen('GetImage', winB, [], 'backBuffer')) / 255;
        mA = local_mean(imgA, [40 40 200 160]);
        mB = local_mean(imgB, [40 40 200 160]);
        fprintf('  panel A [%.2f %.2f %.2f], panel B [%.2f %.2f %.2f]\n', mA, mB);
        t_ok('window A shows its red panel', all(abs(mA - red(1:3)) < 0.08));
        t_ok('window B shows its blue panel', all(abs(mB - blue(1:3)) < 0.08));
        Screen('Flip', winA, [], [], 1);
        Screen('Flip', winB);

        %% the GPU timer
        sA = local_stats(igA);
        fprintf('  GPU time of one Render in A: %.1f us (CPU %.1f us, %d vertices)\n', ...
                sA.frame.renderGpuNs / 1e3, sA.frame.renderCpuNs / 1e3, sA.frame.vertices);
        if vA.gpuTimer
            t_ok('the GPU timer reports a Render time', sA.frame.renderGpuNs > 0);
            t_ok('the GPU time is below one frame', sA.frame.renderGpuNs < 16e6);
        end

        %% the wrong window's context
        Screen('BeginOpenGL', winB);
        PsychImGui('SetContext', igA.ctx);
        t_throws('NewFrame with the other window''s context current', ...
                 'psychimgui:Context', @() PsychImGui('NewFrame', igA.in));
        Screen('EndOpenGL', winB);

        igA = PsychImGuiFrame('Begin', igA);
        PsychImGui('Begin', 'late');
        PsychImGui('End');
        Screen('EndOpenGL', winA);
        Screen('BeginOpenGL', winB);
        t_throws('Render with the other window''s context current', ...
                 'psychimgui:Context', @() PsychImGui('Render'));
        t_ok('the refused Render left no GL error', glGetError() == 0);
        Screen('EndOpenGL', winB);
        Screen('BeginOpenGL', winA);
        PsychImGui('Render');
        Screen('EndOpenGL', winA);
        t_ok('Render in the right context still works', true);

        %% shutting down A from B's context leaves B's objects alone
        Screen('BeginOpenGL', winB);
        lastwarn('');
        ws = warning('off', 'psychimgui:NoGLContext');
        PsychImGui('Shutdown', igA.ctx);
        [~, wid] = lastwarn();
        warning(ws);
        Screen('EndOpenGL', winB);
        t_eq('Shutdown of A in B''s context skips A''s GL objects', wid, ...
             'psychimgui:NoGLContext');
        for f = 1:2
            igB = local_frame(igB, blue);
            if f < 2
                Screen('Flip', winB);
            end
        end
        imgB = double(Screen('GetImage', winB, [], 'backBuffer')) / 255;
        mB = local_mean(imgB, [40 40 200 160]);
        t_ok('B still draws after A went away', all(abs(mB - blue(1:3)) < 0.08));
        Screen('Flip', winB);

        PsychImGuiClose(igA);   % its context is gone; this stops the queue
        PsychImGuiClose(igB);
        [cur, live] = PsychImGui('GetContext');
        t_ok('no context is left', cur == 0 && isempty(live));
        igA = [];
        igB = [];
    catch e
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  test_gl_contexts threw %s: %s\n', e.identifier, e.message);
    end

    PsychImGuiClose(igA);
    PsychImGuiClose(igB);
    if ~isempty(winA) || ~isempty(winB)
        sca;
    end
    clear prefGuard prefGuardB;
    fprintf('test_gl_contexts: %d passed, %d failed\n', TST_PASS, TST_FAIL);
end

function ig = local_frame(ig, color)
    ig = PsychImGuiFrame('Begin', ig);
    flags = {'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize', ...
             'ImGuiWindowFlags_NoScrollbar', 'ImGuiWindowFlags_NoSavedSettings'};
    PsychImGui('PushStyleColor', 'ImGuiCol_WindowBg', color);
    PsychImGui('SetNextWindowPos', [20 20]);
    PsychImGui('SetNextWindowSize', [200 160]);
    PsychImGui('Begin', 'panel', [], flags);
    PsychImGui('End');
    PsychImGui('PopStyleColor');
    PsychImGuiFrame('End', ig);
end

function m = local_mean(img, r)
    inner = img(r(2) + 1:r(4), r(1) + 1:r(3), 1:3);
    m = squeeze(mean(mean(inner, 1), 2))';
end

function s = local_stats(ig)
    PsychImGui('SetContext', ig.ctx);
    s = PsychImGui('Stats');
end
