function test_gl_demo_gabor()
% TEST_GL_DEMO_GABOR  The demo's Gabor really draws a Gabor.
%
%   Needs Psychtoolbox and a GPU. Runs in a few seconds:
%
%       addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
%       test_gl_demo_gabor
%
%   A procedural Gabor fails silently. With PTB's default disableNorm = 0 the
%   shader scales the contrast by 1/(sqrt(2*pi)*sc), about 1/125 for sc = 50,
%   so the demo's contrast of 0.6 drew an amplitude of 0.005 and the patch
%   looked like a plain gray square. Nothing errored. Measured on the
%   development machine, the broken parameters gave a pixel standard deviation
%   of 0.0021 and the fixed ones give 0.0734, so the two are 35 times apart and
%   easy to tell from each other.
%
%   This test pins the fix: the same parameters the demo uses have to produce a
%   patch whose Michelson contrast in the center matches what the slider asked
%   for.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if isempty(TST_PASS); TST_PASS = 0; end
    if isempty(TST_FAIL); TST_FAIL = 0; end

    if exist('Screen', 'file') == 0
        fprintf('SKIP test_gl_demo_gabor: Psychtoolbox is not installed.\n');
        return;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(here));
    addpath(fullfile(root, 'm'), fullfile(root, 'tests'), here);

    win = [];
    try
        [win, rect, prefGuard] = ptb_test_window([0 0 640 480]); %#ok<ASGLU>
        % The [0.5 0.5 0.5 0] background offset is a normalized color, so the
        % window has to read colors the same way.
        Screen('ColorRange', win, 1);

        dst = CenterRectOnPoint([0 0 256 256], rect(3) / 2, rect(4) / 2);
        inner = CenterRectOnPoint([0 0 96 96], rect(3) / 2, rect(4) / 2);

        % Exactly the parameters PsychImGuiDemo uses.
        gabor = CreateProceduralGabor(win, 256, 256, 0, [0.5 0.5 0.5 0], 1, 0.5);

        % A patch at contrast 0 is the control: it is the flat gray square the
        % broken normalization used to draw at every contrast.
        local_draw(win, gabor, dst, 0);
        flat = gabor_std(win, dst);
        Screen('Flip', win);
        t_ok('a zero contrast patch is flat', flat < 0.01);

        local_draw(win, gabor, dst, 0.6);
        s = gabor_std(win, dst);
        img = double(Screen('GetImage', win, inner, 'backBuffer')) / 255;
        Screen('Flip', win);

        lo = min(img(:));
        hi = max(img(:));
        michelson = (hi - lo) / (hi + lo);
        fprintf('  contrast 0.6: pixel std %.4f, central min %.3f max %.3f, Michelson %.3f\n', ...
                s, lo, hi, michelson);

        t_ok('the patch is not flat', s > 0.02);
        t_ok('the patch is far from the broken normalization', s > 10 * max(flat, 1e-4));
        % disableNorm = 1 with contrastPreMultiplicator = 0.5 means the
        % contrast argument is the Michelson contrast of the patch.
        t_ok('the slider value is the Michelson contrast', abs(michelson - 0.6) < 0.05);
        t_ok('the patch swings either side of the gray', lo < 0.35 && hi > 0.65);

        % The standard deviation has to follow the contrast, or the slider is
        % not driving what it claims to drive.
        local_draw(win, gabor, dst, 0.3);
        half = gabor_std(win, dst);
        Screen('Flip', win);
        fprintf('  contrast 0.3: pixel std %.4f (half of %.4f is %.4f)\n', ...
                half, s, s / 2);
        t_ok('halving the contrast halves the modulation', abs(half - s / 2) < 0.01);
    catch e
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  test_gl_demo_gabor threw %s: %s\n', e.identifier, e.message);
    end

    if ~isempty(win)
        sca;
    end
    clear prefGuard;
    fprintf('test_gl_demo_gabor: %d passed, %d failed\n', TST_PASS, TST_FAIL);
end

function local_draw(win, gabor, dst, contrast)
    Screen('DrawTexture', win, gabor, [], dst, 45, [], [], [1 1 1 0], [], ...
           kPsychDontDoRotation, [180, 0.03, 50, contrast, 1, 0, 0, 0]);
end
