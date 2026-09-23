function test_gl_phase2(renderer)
% TEST_GL_PHASE2  Tables, draw lists, and Image in a real PTB window.
%
%   Needs Psychtoolbox and a GPU. run_tests does not call this file; run it by
%   hand on a developer machine:
%
%       addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
%       test_gl_phase2               % the backend Init picks
%       test_gl_phase2('opengl2')    % the fixed function backend macOS gets
%
%   One frame draws three images, a table with colored cells, and a set of draw
%   list primitives at known places, then reads the frame back with
%   Screen('GetImage') and checks the colors there.
%
%   The images are what the headless suite cannot check. PTB stores a
%   texture made from a matrix transposed and an offscreen window bottom row
%   first, and both are drawn from a test pattern with a different color in
%   each quadrant, so a transposed, mirrored, or black image fails.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if isempty(TST_PASS); TST_PASS = 0; end
    if isempty(TST_FAIL); TST_FAIL = 0; end
    if nargin < 1
        renderer = 'auto';
    end

    % exist(...,'file') answers 2 for Screen when its help M-file is also on
    % the path, so only a zero means Psychtoolbox is really absent.
    if exist('Screen', 'file') == 0
        fprintf('SKIP test_gl_phase2: Psychtoolbox is not installed.\n');
        return;
    end
    % Psychtoolbox on the path is not enough: on Octave for Windows its
    % Screen.mex can fail to load for a missing DLL. That is a setup problem,
    % not a binding failure, so skip with the reason.
    try
        Screen('Version');
    catch e
        fprintf('SKIP test_gl_phase2: Screen does not load (%s).\n', e.message);
        return;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(here));
    addpath(fullfile(root, 'm'), fullfile(root, 'tests'), here);
    PsychImGuiSetup();

    win = [];
    ig = [];
    try
        [win, rect, prefGuard] = ptb_test_window([0 0 640 480]); %#ok<ASGLU>
        ig = PsychImGuiOpen(win, struct('renderer', renderer));
        v = PsychImGui('Version');
        fprintf('  renderer %s on %s\n', v.renderer, v.glVersion);

        % Quadrants, top left red, top right green, bottom left blue, bottom
        % right white. 32 rows by 64 columns, so a transposed draw also
        % changes the aspect and cannot pass by symmetry.
        pattern = zeros(32, 64, 3, 'uint8');
        pattern(1:16, 1:32, 1) = 255;
        pattern(1:16, 33:64, 2) = 255;
        pattern(17:32, 1:32, 3) = 255;
        pattern(17:32, 33:64, :) = 255;
        quads = {[1 0 0], [0 1 0], [0 0 1], [1 1 1]};

        % specialFlags 1 asks PTB for GL_TEXTURE_2D, which Dear ImGui samples.
        ptbTex = Screen('MakeTexture', win, pattern, [], 1);
        tex = PsychImGuiImage(ig, ptbTex, 'nearest');
        t_eq('a MakeTexture texture is GL_TEXTURE_2D', tex.glTarget, 3553);
        t_eq('a MakeTexture texture is transposed', tex.orientation, 'transposed');
        t_eq('the descriptor has the image size', tex.size, [64 32]);

        % An offscreen window with specialFlags 1 is GL_TEXTURE_2D as well,
        % stored bottom row first.
        off = Screen('OpenOffscreenWindow', win, 0, [0 0 64 32], [], 1);
        Screen('FillRect', off, [255 0 0], [0 0 32 16]);
        Screen('FillRect', off, [0 255 0], [32 0 64 16]);
        Screen('FillRect', off, [0 0 255], [0 16 32 32]);
        Screen('FillRect', off, [255 255 255], [32 16 64 32]);
        offTex = PsychImGuiImage(ig, off, 'nearest');
        t_eq('an offscreen window is upright', offTex.orientation, 'upright');

        % A PTB default texture is GL_TEXTURE_RECTANGLE, which the backends
        % cannot bind. Both layers refuse it with the same identifier.
        rectTex = Screen('MakeTexture', win, pattern);
        t_throws('PsychImGuiImage refuses a rectangle texture', 'psychimgui:Texture', ...
                 @() PsychImGuiImage(ig, rectTex));
        rectId = Screen('GetOpenGLTexture', win, rectTex);
        t_throws('SetTextureFilter refuses a rectangle texture', 'psychimgui:Texture', ...
                 @() PsychImGuiGL(ig, 'SetTextureFilter', rectId));
        t_ok('the refused filter call left 2D mode', local_draw_mode() == 0);

        imgA = [20 20];            % transposed texture, drawn 4x, nearest
        imgB = [20 170];           % upright texture, drawn 4x, nearest
        imgC = [20 300];           % imgA again, linear
        texLinear = tex;
        texLinear.filter = 'linear';
        imgSize = [256 128];
        tablePos = [320 20];
        cellA = [];
        cellB = [];
        staleHandle = [];
        bare = {'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize', ...
                'ImGuiWindowFlags_NoScrollbar', 'ImGuiWindowFlags_NoSavedSettings', ...
                'ImGuiWindowFlags_NoBackground'};

        for f = 1:3
            ig = PsychImGuiFrame('Begin', ig);

            % Zero padding and border, so each image starts at its window's
            % corner and the quadrant centers are known.
            PsychImGui('PushStyleVarVec2', 'ImGuiStyleVar_WindowPadding', [0 0]);
            PsychImGui('PushStyleVar', 'ImGuiStyleVar_WindowBorderSize', 0);
            PsychImGui('SetNextWindowPos', imgA);
            PsychImGui('SetNextWindowSize', imgSize);
            PsychImGui('Begin', 'imgA', [], bare);
            PsychImGui('Image', tex, imgSize);
            PsychImGui('End');
            PsychImGui('SetNextWindowPos', imgB);
            PsychImGui('SetNextWindowSize', imgSize);
            PsychImGui('Begin', 'imgB', [], bare);
            PsychImGui('Image', offTex, imgSize);
            PsychImGui('End');
            PsychImGui('SetNextWindowPos', imgC);
            PsychImGui('SetNextWindowSize', imgSize);
            PsychImGui('Begin', 'imgC', [], bare);
            PsychImGui('Image', texLinear, imgSize);
            PsychImGui('End');
            PsychImGui('PopStyleVar', 2);

            PsychImGui('SetNextWindowPos', tablePos);
            PsychImGui('SetNextWindowSize', [300 130]);
            PsychImGui('Begin', 'table', [], bare);
            if PsychImGui('BeginTable', 'grid', 2)
                PsychImGui('TableNextRow', 0, 40);
                PsychImGui('TableNextColumn');
                cellA = PsychImGui('GetCursorScreenPos');
                PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_CellBg', [0 0 1 1]);
                PsychImGui('Text', 'a');
                PsychImGui('TableNextColumn');
                cellB = PsychImGui('GetCursorScreenPos');
                PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_CellBg', [0 1 0 1]);
                PsychImGui('Text', 'b');
                PsychImGui('EndTable');
            end
            % ImageButton goes through the same path as Image; it only has to
            % render without a GL error here.
            PsychImGui('ImageButton', 'btn', tex, [32 16]);
            PsychImGui('End');

            fg = PsychImGui('GetForegroundDrawList');
            bg = PsychImGui('GetBackgroundDrawList');
            PsychImGui('DrawList.AddRectFilled', fg, [320 180], [400 240], [1 1 0 1]);
            PsychImGui('DrawList.PushClipRect', fg, [440 180], [480 240]);
            PsychImGui('DrawList.AddRectFilled', fg, [420 180], [500 240], [1 0 1 1]);
            PsychImGui('DrawList.PopClipRect', fg);
            PsychImGui('DrawList.AddCircleFilled', fg, [560 210], 25, [0 1 1 1]);
            PsychImGui('DrawList.AddConvexPolyFilled', fg, ...
                       [320 320; 380 320; 380 380; 320 380], [1 0.5 0 1]);
            PsychImGui('DrawList.AddRectFilled', bg, [560 400], [620 460], [1 1 1 1]);
            PsychImGui('DrawList.AddLine', fg, [400 300], [500 300], [1 1 1 1], 3);
            PsychImGui('DrawList.AddRect', fg, [400 320], [460 380], [1 1 1 1], 4, 2);
            PsychImGui('DrawList.AddCircle', fg, [500 350], 20, [1 1 1 1]);
            PsychImGui('DrawList.AddTriangle', fg, [400 400], [440 400], [420 440], [1 1 1 1]);
            PsychImGui('DrawList.AddTriangleFilled', fg, [460 400], [500 400], ...
                       [480 440], [1 1 1 1]);
            PsychImGui('DrawList.AddPolyline', fg, [320 400; 340 440; 360 400], ...
                       [1 1 1 1], 2);
            PsychImGui('DrawList.AddText', fg, [20 440], [1 1 1 1], 'draw list text');
            staleHandle = fg;

            PsychImGuiFrame('End', ig);
            if f < 3
                Screen('Flip', win);
            end
        end

        % Read the back buffer before the flip; after a flip it is undefined.
        img = double(Screen('GetImage', win, [], 'backBuffer')) / 255;
        Screen('Flip', win);

        t_throws('a draw list handle is stale after the frame', ...
                 'psychimgui:InvalidHandle', ...
                 @() PsychImGui('DrawList.AddLine', staleHandle, [0 0], [1 1], [1 1 1 1]));

        %% images
        names = {'top left', 'top right', 'bottom left', 'bottom right'};
        centers = [64 32; 192 32; 64 96; 192 96];
        for q = 1:4
            got = local_pixel(img, imgA + centers(q, :));
            fprintf('  transposed %-12s [%.2f %.2f %.2f]\n', names{q}, got);
            t_ok(['transposed texture ' names{q}], all(abs(got - quads{q}) < 0.1));
            got = local_pixel(img, imgB + centers(q, :));
            fprintf('  upright    %-12s [%.2f %.2f %.2f]\n', names{q}, got);
            t_ok(['upright texture ' names{q}], all(abs(got - quads{q}) < 0.1));
        end

        % The filter. The quadrant edge sits at x = 128 in the 4x image; x =
        % 127 is 1.5 texels from the centers on either side. The OpenGL 3
        % backend samples through its own linear sampler on GL 3.3 and later,
        % so 'nearest' only holds if the sampler callbacks reach it.
        sharp = local_pixel(img, imgA + [127 32]);
        soft = local_pixel(img, imgC + [127 32]);
        fprintf('  edge pixel nearest [%.2f %.2f %.2f], linear [%.2f %.2f %.2f]\n', ...
                sharp, soft);
        t_ok('nearest keeps the quadrant edge sharp', all(abs(sharp - [1 0 0]) < 0.1));
        t_ok('linear blends across the quadrant edge', ...
             soft(1) > 0.2 && soft(1) < 0.9 && soft(2) > 0.1 && soft(2) < 0.8);

        %% table cells
        t_ok('the table opened', ~isempty(cellA) && ~isempty(cellB));
        if ~isempty(cellA)
            % Right of the one letter label, inside the 40 pixel row.
            a = local_pixel(img, cellA + [60 20]);
            b = local_pixel(img, cellB + [60 20]);
            fprintf('  cell a [%.2f %.2f %.2f], cell b [%.2f %.2f %.2f]\n', a, b);
            t_ok('cell a background is blue', all(abs(a - [0 0 1]) < 0.1));
            t_ok('cell b background is green', all(abs(b - [0 1 0]) < 0.1));
        end

        %% draw list primitives
        checks = { ...
            'filled rectangle', [360 210], [1 1 0]; ...
            'inside the clip rectangle', [460 210], [1 0 1]; ...
            'left of the clip rectangle', [430 210], [0 0 0]; ...
            'right of the clip rectangle', [490 210], [0 0 0]; ...
            'filled circle', [560 210], [0 1 1]; ...
            'convex polygon', [350 350], [1 0.5 0]; ...
            'background draw list', [590 430], [1 1 1]};
        for k = 1:size(checks, 1)
            got = local_pixel(img, checks{k, 2});
            fprintf('  %-28s [%.2f %.2f %.2f]\n', checks{k, 1}, got);
            t_ok(['draw list ' checks{k, 1}], all(abs(got - checks{k, 3}) < 0.1));
        end

        % Render must leave glGetError clean, or Screen('EndOpenGL') aborts
        % the script. This is rule R3.
        ig = PsychImGuiFrame('Begin', ig);
        PsychImGui('Image', tex, [64 32]);
        err = glGetError();
        PsychImGuiFrame('End', ig);
        t_ok('Render leaves GL_NO_ERROR', err == 0);

        PsychImGuiClose(ig);
        ig = [];
    catch e
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  test_gl_phase2 threw %s: %s\n', e.identifier, e.message);
    end

    PsychImGuiClose(ig);
    if ~isempty(win)
        sca;
    end
    clear prefGuard;   % restores the preferences this run changed
    fprintf('test_gl_phase2: %d passed, %d failed\n', TST_PASS, TST_FAIL);
end

function rgb = local_pixel(img, xy)
    % xy is in window pixels from the top left corner, 0 based.
    rgb = squeeze(img(round(xy(2)) + 1, round(xy(1)) + 1, 1:3))';
end

function mode = local_draw_mode()
    [~, mode] = Screen('GetOpenGLDrawMode');
end
