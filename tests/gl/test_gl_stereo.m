function test_gl_stereo(modes)
% TEST_GL_STEREO  The GUI appears in both eyes of a Psychtoolbox stereo mode.
%
%   Needs Psychtoolbox and a GPU. run_tests does not call this file; run it by
%   hand on a developer machine:
%
%       addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
%       test_gl_stereo           % modes 4 and 8, both work on one display
%       test_gl_stereo(4)
%
%   Mode 4 splits one window into a left and a right half, and mode 8 is
%   red-blue anaglyph. With the imaging pipeline, which PsychImaging always
%   enables, each eye is a framebuffer object of its own that
%   Screen('SelectStereoDrawBuffer') selects and Screen('BeginOpenGL') binds.
%   PsychImGuiFrame('End') renders the frame into eye 0 and submits it again
%   into eye 1. The test reads each eye's framebuffer back through
%   Screen('GetImage', win, [], 'drawBuffer') after selecting the eye, and a
%   control frame that submits only eye 0 shows that the check can fail.
%
%   'backLeftBuffer' and 'backRightBuffer' do not work here. SCREENGetImage.c
%   accepts them only for a quad buffered framebuffer or modes 11 and 12, and
%   in modes 4 and 8 Screen answers "Invalid or unknown 'bufferName'" and
%   closes every window with the error.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if isempty(TST_PASS); TST_PASS = 0; end
    if isempty(TST_FAIL); TST_FAIL = 0; end
    if nargin < 1
        modes = [4 8];
    end

    if exist('Screen', 'file') == 0
        fprintf('SKIP test_gl_stereo: Psychtoolbox is not installed.\n');
        return;
    end
    try
        Screen('Version');
    catch e
        fprintf('SKIP test_gl_stereo: Screen does not load (%s).\n', e.message);
        return;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(here));
    addpath(fullfile(root, 'm'), fullfile(root, 'tests'), here);
    PsychImGuiSetup();

    for mode = modes
        local_one_mode(mode);
    end
    fprintf('test_gl_stereo: %d passed, %d failed\n', TST_PASS, TST_FAIL);
end

function local_one_mode(mode)
    global TST_FAIL %#ok<GVMIS>
    win = [];
    ig = [];
    green = [0.1 0.8 0.2 1];
    panel = [20 20 180 120];
    try
        [win, rect, prefGuard] = ptb_test_window([0 0 640 480], mode); %#ok<ASGLU>
        fprintf('  mode %d: eye rectangle [%d %d %d %d]\n', mode, rect);
        ig = PsychImGuiOpen(win);
        t_ok(sprintf('mode %d: the handle knows the window is stereo', mode), ig.stereo);

        for f = 1:3
            ig = local_frame(ig, green, panel);
            PsychImGuiFrame('End', ig);
            if f < 3
                Screen('Flip', win);
            end
        end
        for eye = 0:1
            m = local_eye_mean(win, eye, panel);
            fprintf('  mode %d eye %d: panel [%.2f %.2f %.2f]\n', mode, eye, m);
            t_ok(sprintf('mode %d: eye %d shows the panel', mode, eye), ...
                 all(abs(m - green(1:3)) < 0.1));
        end
        Screen('Flip', win);

        % Control: build the frame and submit it to eye 0 only. Eye 1 must
        % stay black, or the check above proves nothing.
        ig = local_frame(ig, green, panel);
        Screen('EndOpenGL', win);
        Screen('SelectStereoDrawBuffer', win, 0);
        Screen('BeginOpenGL', win);
        PsychImGui('Render');
        Screen('EndOpenGL', win);
        m0 = local_eye_mean(win, 0, panel);
        m1 = local_eye_mean(win, 1, panel);
        fprintf('  mode %d control: eye 0 [%.2f %.2f %.2f], eye 1 [%.2f %.2f %.2f]\n', ...
                mode, m0, m1);
        t_ok(sprintf('mode %d control: eye 0 has the panel', mode), ...
             all(abs(m0 - green(1:3)) < 0.1));
        t_ok(sprintf('mode %d control: eye 1 without RenderAgain is empty', mode), ...
             max(m1) < 0.05);
        Screen('Flip', win);

        s = PsychImGui('Stats');
        t_ok(sprintf('mode %d: RenderAgain ran', mode), ...
             any(strcmp({s.perOp.name}, 'RenderAgain')));

        PsychImGuiClose(ig);
        ig = [];
    catch e
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  test_gl_stereo mode %d threw %s: %s\n', mode, ...
                e.identifier, e.message);
    end
    PsychImGuiClose(ig);
    if ~isempty(win)
        sca;
    end
    clear prefGuard;
end

function ig = local_frame(ig, color, r)
    ig = PsychImGuiFrame('Begin', ig);
    flags = {'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize', ...
             'ImGuiWindowFlags_NoScrollbar', 'ImGuiWindowFlags_NoSavedSettings'};
    PsychImGui('PushStyleColor', 'ImGuiCol_WindowBg', color);
    PsychImGui('SetNextWindowPos', r(1:2));
    PsychImGui('SetNextWindowSize', r(3:4) - r(1:2));
    PsychImGui('Begin', 'stereo panel', [], flags);
    PsychImGui('End');
    PsychImGui('PopStyleColor');
end

function m = local_eye_mean(win, eye, r)
    Screen('SelectStereoDrawBuffer', win, eye);
    img = double(Screen('GetImage', win, [], 'drawBuffer')) / 255;
    inner = img(r(2) + 20:r(4) - 20, r(1) + 20:r(3) - 20, 1:3);
    m = squeeze(mean(mean(inner, 1), 2))';
end
