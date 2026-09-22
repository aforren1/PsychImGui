function test_gl_render()
% TEST_GL_RENDER  Draw a PsychImGui window into a real PTB window and read it back.
%
%   Needs Psychtoolbox and a GPU. run_tests does not call this file; run it by
%   hand on a developer machine:
%
%       addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
%       test_gl_render
%
%   The test opens a 640x480 window, draws one PsychImGui window filled with a
%   known background color, flips, reads the frame back with Screen('GetImage'),
%   and checks the mean color inside the window rectangle.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if isempty(TST_PASS); TST_PASS = 0; end
    if isempty(TST_FAIL); TST_FAIL = 0; end

    if exist('Screen', 'file') ~= 3
        fprintf('SKIP test_gl_render: Psychtoolbox is not installed.\n');
        return;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(here));
    addpath(fullfile(root, 'm'), fullfile(root, 'tests'), here);
    PsychImGuiSetup();

    win = [];
    try
        % ptb_test_window sets SkipSyncTests and VisualDebugLevel, so a test run
        % pays for neither the display timing calibration nor the splash screen.
        [win, rect, prefGuard] = ptb_test_window([0 0 640 480]); %#ok<ASGLU>

        Screen('BeginOpenGL', win);
        PsychImGui('Init', win, rect, PsychImGuiKeymap());
        Screen('EndOpenGL', win);

        v = PsychImGui('Version');
        t_ok('renderer is opengl3', strcmp(v.renderer, 'opengl3'));
        t_ok('GL version string is present', ~isempty(v.glVersion));

        % A window with no decoration and an opaque red background is easy to
        % find again in the read back image.
        bg = [0.8 0.1 0.1 1.0];
        winRect = [40 40 340 240];

        for f = 1:3
            in = PsychImGuiInput('Empty', rect);
            in.time = f / 60;
            Screen('BeginOpenGL', win);
            PsychImGui('NewFrame', in);
            PsychImGui('PushStyleColor', 'ImGuiCol_WindowBg', bg);
            PsychImGui('SetNextWindowPos', winRect(1:2));
            PsychImGui('SetNextWindowSize', [winRect(3) - winRect(1), ...
                                             winRect(4) - winRect(2)]);
            flags = {'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize', ...
                     'ImGuiWindowFlags_NoScrollbar', 'ImGuiWindowFlags_NoSavedSettings'};
            PsychImGui('Begin', 'glTest', [], flags);
            PsychImGui('End');
            PsychImGui('PopStyleColor');
            PsychImGui('Render');
            Screen('EndOpenGL', win);
            if f < 3
                % Dear ImGui hides a window on the frame it first appears,
                % while it auto-fits, so read back only after a few frames.
                Screen('Flip', win);
            end
        end

        % Read the back buffer before the flip. After a flip the back buffer
        % holds undefined contents.
        img = Screen('GetImage', win, [], 'backBuffer');
        Screen('Flip', win);
        inner = double(img(winRect(2) + 20 : winRect(4) - 20, ...
                           winRect(1) + 20 : winRect(3) - 20, :)) / 255;
        m = [mean(mean(inner(:, :, 1))), mean(mean(inner(:, :, 2))), ...
             mean(mean(inner(:, :, 3)))];
        fprintf('  mean inner color [%.3f %.3f %.3f], expected [%.3f %.3f %.3f]\n', ...
                m, bg(1:3));
        t_ok('window background color matches', all(abs(m - bg(1:3)) < 0.08));

        outer = double(img(10:30, 10:30, :)) / 255;
        t_ok('outside the window stays black', mean(outer(:)) < 0.05);

        s = PsychImGui('Stats');
        t_ok('Render produced vertices', s.frame.vertices > 0);

        % ImPlot draws through the same backend, so one plot frame proves the
        % extension renders too.
        if v.implot
            for f = 1:3
                Screen('BeginOpenGL', win);
                PsychImGui('NewFrame', PsychImGuiInput('Empty', rect));
                PsychImGui('SetNextWindowSize', [400 300]);
                PsychImGui('Begin', 'plotTest');
                if PsychImGui('ImPlot.BeginPlot', 'trace', [-1 200])
                    PsychImGui('ImPlot.PlotLine', 'sin', sin(linspace(0, 6, 256)));
                    PsychImGui('ImPlot.PlotHeatmap', 'grid', rand(8, 8));
                    PsychImGui('ImPlot.EndPlot');
                end
                PsychImGui('End');
                PsychImGui('Render');
                Screen('EndOpenGL', win);
                Screen('Flip', win);
            end
            sp = PsychImGui('Stats');
            t_ok('ImPlot frame produced vertices', sp.frame.vertices > 0);
        end

        % Render must leave glGetError clean, or Screen('EndOpenGL') aborts the
        % script. This is rule R3.
        Screen('BeginOpenGL', win);
        PsychImGui('NewFrame', PsychImGuiInput('Empty', rect));
        PsychImGui('Render');
        err = glGetError();
        Screen('EndOpenGL', win);
        t_ok('Render leaves GL_NO_ERROR', err == 0);

        Screen('BeginOpenGL', win);
        PsychImGui('Shutdown');
        Screen('EndOpenGL', win);
    catch e
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  test_gl_render threw %s: %s\n', e.identifier, e.message);
    end

    try
        PsychImGui('Shutdown');
    catch
    end
    if ~isempty(win)
        sca;
    end
    clear prefGuard;   % restores the preferences this run changed
    fprintf('test_gl_render: %d passed, %d failed\n', TST_PASS, TST_FAIL);
end
