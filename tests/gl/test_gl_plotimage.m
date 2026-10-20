function test_gl_plotimage(renderer)
% TEST_GL_PLOTIMAGE  ImPlot.PlotImage and ImPlot3D.PlotImage, pixel by pixel.
%
%   test_gl_plotimage()             % the backend PsychImGuiOpen picks
%   test_gl_plotimage('opengl2')    % the fixed function backend
%
%   PTB stores a texture made from a matrix transposed. Both subcommands must
%   show it upright, as Image does. The test pattern has a different color in
%   each quadrant, so a transposed or mirrored image fails. The quadrant
%   centers come from the plots themselves: GetPlotPos and GetPlotSize in 2D,
%   PlotToPixels in 3D.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if isempty(TST_PASS); TST_PASS = 0; end
    if isempty(TST_FAIL); TST_FAIL = 0; end
    if nargin < 1
        renderer = 'auto';
    end
    if exist('Screen', 'file') == 0
        fprintf('SKIP test_gl_plotimage: Psychtoolbox is not installed.\n');
        return;
    end
    try
        Screen('Version');
    catch e
        fprintf('SKIP test_gl_plotimage: Screen does not load (%s).\n', e.message);
        return;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(here));
    addpath(fullfile(root, 'm'), fullfile(root, 'tests'), here);
    PsychImGuiSetup();

    win = [];
    ig = [];
    try
        [win, ~, prefGuard] = ptb_test_window([0 0 640 480]);
        ig = PsychImGuiOpen(win, struct('renderer', renderer));
        v = PsychImGui('Version');
        fprintf('  renderer %s on %s\n', v.renderer, v.glVersion);

        % Top left red, top right green, bottom left blue, bottom right white.
        pattern = zeros(32, 64, 3, 'uint8');
        pattern(1:16, 1:32, 1) = 255;
        pattern(1:16, 33:64, 2) = 255;
        pattern(17:32, 1:32, 3) = 255;
        pattern(17:32, 33:64, :) = 255;
        quads = {[1 0 0], [0 1 0], [0 0 1], [1 1 1]};
        names = {'top left', 'top right', 'bottom left', 'bottom right'};
        % Quadrant centers in image coordinates, 0 to 1 from the top left.
        uvCenters = [0.25 0.25; 0.75 0.25; 0.25 0.75; 0.75 0.75];

        ptbTex = Screen('MakeTexture', win, pattern, [], 1);
        transposed = PsychImGuiImage(ig, ptbTex, 'nearest');
        off = Screen('OpenOffscreenWindow', win, 0, [0 0 64 32], [], 1);
        Screen('FillRect', off, [255 0 0], [0 0 32 16]);
        Screen('FillRect', off, [0 255 0], [32 0 64 16]);
        Screen('FillRect', off, [0 0 255], [0 16 32 32]);
        Screen('FillRect', off, [255 255 255], [32 16 64 32]);
        upright = PsychImGuiImage(ig, off, 'nearest');

        bare = {'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize', ...
                'ImGuiWindowFlags_NoScrollbar', 'ImGuiWindowFlags_NoSavedSettings', ...
                'ImGuiWindowFlags_NoBackground'};
        noDeco = 'ImPlotAxisFlags_NoDecorations';
        texs = {transposed, upright};
        plotRect = zeros(2, 4);
        pix3 = zeros(4, 2);

        for f = 1:3
            ig = PsychImGuiFrame('Begin', ig);
            PsychImGui('PushStyleVarVec2', 'ImGuiStyleVar_WindowPadding', [0 0]);
            PsychImGui('ImPlot.PushStyleVarVec2', 'ImPlotStyleVar_PlotPadding', [0 0]);
            for k = 1:2
                PsychImGui('SetNextWindowPos', [20 + 300 * (k - 1), 20]);
                PsychImGui('SetNextWindowSize', [256 128]);
                PsychImGui('Begin', sprintf('plot%d', k), [], bare);
                if PsychImGui('ImPlot.BeginPlot', sprintf('##p%d', k), [256 128], ...
                              'ImPlotFlags_CanvasOnly')
                    PsychImGui('ImPlot.SetupAxes', '', '', noDeco, noDeco);
                    PsychImGui('ImPlot.SetupAxesLimits', 0, 1, 0, 1, 'ImPlotCond_Always');
                    PsychImGui('ImPlot.PlotImage', 'img', texs{k}, [0 0], [1 1]);
                    plotRect(k, :) = [PsychImGui('ImPlot.GetPlotPos'), ...
                                      PsychImGui('ImPlot.GetPlotSize')];
                    PsychImGui('ImPlot.EndPlot');
                end
                PsychImGui('End');
            end

            PsychImGui('SetNextWindowPos', [20 180]);
            PsychImGui('SetNextWindowSize', [300 280]);
            PsychImGui('Begin', 'plot3d', [], bare);
            if PsychImGui('ImPlot3D.BeginPlot', '##p3', [300 280], 'ImPlot3DFlags_CanvasOnly')
                PsychImGui('ImPlot3D.SetupAxesLimits', 0, 1, 0, 1, 0, 1, 'ImPlot3DCond_Always');
                PsychImGui('ImPlot3D.SetupBoxRotation', 90, 0, false, 'ImPlot3DCond_Always');
                % The image in the z = 0.5 plane, top left at (0, 1).
                corners = [0 1 0.5; 1 1 0.5; 1 0 0.5; 0 0 0.5];
                PsychImGui('ImPlot3D.PlotImage', 'img', transposed, corners);
                for q = 1:4
                    u = uvCenters(q, 1);
                    w = uvCenters(q, 2);
                    pix3(q, :) = PsychImGui('ImPlot3D.PlotToPixels', u, 1 - w, 0.5);
                end
                PsychImGui('ImPlot3D.EndPlot');
            end
            PsychImGui('End');
            PsychImGui('ImPlot.PopStyleVar');
            PsychImGui('PopStyleVar');

            PsychImGuiFrame('End', ig);
            if f < 3
                Screen('Flip', win);
            end
        end
        img = double(Screen('GetImage', win, [], 'backBuffer')) / 255;
        Screen('Flip', win);

        labels = {'transposed', 'upright'};
        for k = 1:2
            pos = plotRect(k, 1:2);
            sz = plotRect(k, 3:4);
            t_ok(sprintf('the %s plot opened', labels{k}), all(sz > 0));
            for q = 1:4
                got = local_pixel(img, pos + uvCenters(q, :) .* sz);
                fprintf('  2D %-10s %-12s [%.2f %.2f %.2f]\n', labels{k}, names{q}, got);
                t_ok(sprintf('ImPlot.PlotImage %s %s', labels{k}, names{q}), ...
                     all(abs(got - quads{q}) < 0.1));
            end
        end
        for q = 1:4
            got = local_pixel(img, pix3(q, :));
            fprintf('  3D transposed %-12s [%.2f %.2f %.2f]\n', names{q}, got);
            t_ok(sprintf('ImPlot3D.PlotImage transposed %s', names{q}), ...
                 all(abs(got - quads{q}) < 0.15));
        end

        PsychImGuiClose(ig);
        ig = [];
        Screen('Close', win);
        win = [];
    catch e
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  test_gl_plotimage threw %s: %s\n', e.identifier, e.message);
        if ~isempty(ig)
            try PsychImGuiClose(ig); catch, end
        end
        if ~isempty(win)
            try Screen('Close', win); catch, end
        end
    end
    clear prefGuard;
    fprintf('test_gl_plotimage: %d passed, %d failed\n', TST_PASS, TST_FAIL);
end

function rgb = local_pixel(img, xy)
    rgb = squeeze(img(round(xy(2)) + 1, round(xy(1)) + 1, 1:3))';
end
