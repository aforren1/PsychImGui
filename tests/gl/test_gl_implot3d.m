function test_gl_implot3d(renderer)
% TEST_GL_IMPLOT3D  A 3D line plot, a surface, and a mesh in a PTB window.
%
%   Needs Psychtoolbox and a GPU. run_tests does not call this file; run it by
%   hand on a developer machine:
%
%       addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
%       test_gl_implot3d               % the backend Init picks
%       test_gl_implot3d('opengl2')    % the fixed function backend
%
%   One plot holds a red helix, and the test checks that red pixels appear
%   and that ImPlot3D.PlotToPixels maps a point of the helix onto one of
%   them. A second plot holds a blue mesh triangle given as a 1-based Faces
%   matrix, so a transposed or 0-based index list would draw the wrong
%   triangle or none.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if isempty(TST_PASS); TST_PASS = 0; end
    if isempty(TST_FAIL); TST_FAIL = 0; end
    if nargin < 1
        renderer = 'auto';
    end

    if exist('Screen', 'file') == 0
        fprintf('SKIP test_gl_implot3d: Psychtoolbox is not installed.\n');
        return;
    end
    try
        Screen('Version');
    catch e
        fprintf('SKIP test_gl_implot3d: Screen does not load (%s).\n', e.message);
        return;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(fileparts(here));
    addpath(fullfile(root, 'm'), fullfile(root, 'tests'), here);
    PsychImGuiSetup();

    win = [];
    ig = [];
    try
        [win, ~, prefGuard] = ptb_test_window([0 0 640 480]); %#ok<ASGLU>
        ig = PsychImGuiOpen(win, struct('renderer', renderer));
        v = PsychImGuiGL(ig, 'Version');
        if ~v.implot3d
            fprintf('SKIP test_gl_implot3d: ImPlot3D is not compiled in.\n');
            PsychImGuiClose(ig);
            ig = [];
            sca;
            return;
        end
        fprintf('  renderer %s, ImPlot3D %s\n', v.renderer, v.implot3dVersion);

        t = linspace(0, 4 * pi, 400);
        x = cos(t);
        y = sin(t);
        z = t / (2 * pi) - 1;
        [gx, gy] = meshgrid(linspace(-1, 1, 20), linspace(-1, 1, 20));
        gz = 0.3 * exp(-2 * (gx .^ 2 + gy .^ 2)) - 0.9;
        vx = [-1 1 0 0];
        vy = [-1 -1 1 0];
        vz = [0 0 0 1];
        faces = [1 2 3];
        pix = [];
        bare = {'ImGuiWindowFlags_NoTitleBar', 'ImGuiWindowFlags_NoResize', ...
                'ImGuiWindowFlags_NoSavedSettings'};

        for f = 1:4
            ig = PsychImGuiFrame('Begin', ig);
            PsychImGui('SetNextWindowPos', [0 0]);
            PsychImGui('SetNextWindowSize', [320 480]);
            PsychImGui('Begin', 'helix', [], bare);
            if PsychImGui('ImPlot3D.BeginPlot', 'trajectory', [-1 -1])
                PsychImGui('ImPlot3D.SetupAxesLimits', -1.2, 1.2, -1.2, 1.2, -1, 1, ...
                           'ImPlot3DCond_Always');
                PsychImGui('ImPlot3D.PlotLine', 'helix', x, y, z, ...
                           'LineColor', [1 0 0 1], 'LineWeight', 3);
                PsychImGui('ImPlot3D.PlotSurface', 'floor', gx, gy, gz);
                pix = PsychImGui('ImPlot3D.PlotToPixels', x(100), y(100), z(100));
                PsychImGui('ImPlot3D.EndPlot');
            end
            PsychImGui('End');
            PsychImGui('SetNextWindowPos', [320 0]);
            PsychImGui('SetNextWindowSize', [320 480]);
            PsychImGui('Begin', 'mesh', [], bare);
            if PsychImGui('ImPlot3D.BeginPlot', 'mesh', [-1 -1], ...
                          'ImPlot3DFlags_NoLegend')
                PsychImGui('ImPlot3D.SetupAxesLimits', -1, 1, -1, 1, -1, 1, ...
                           'ImPlot3DCond_Always');
                PsychImGui('ImPlot3D.SetupBoxRotation', 90, 0, false, ...
                           'ImPlot3DCond_Always');
                PsychImGui('ImPlot3D.PlotMesh', 'tri', vx, vy, vz, faces, ...
                           'FillColor', [0 0.3 1 1], 'LineColor', [0 0.3 1 1]);
                PsychImGui('ImPlot3D.EndPlot');
            end
            PsychImGui('End');
            PsychImGuiFrame('End', ig);
            if f < 4
                Screen('Flip', win);
            end
        end

        img = double(Screen('GetImage', win, [], 'backBuffer')) / 255;
        Screen('Flip', win);
        r = img(:, :, 1);
        g = img(:, :, 2);
        b = img(:, :, 3);
        red = r > 0.7 & g < 0.3 & b < 0.3;
        blue = b > 0.7 & r < 0.3 & g > 0.1 & g < 0.5;
        nRedLeft = nnz(red(:, 1:320));
        nBlueRight = nnz(blue(:, 321:640));
        fprintf('  red pixels in the helix plot %d, blue pixels in the mesh plot %d\n', ...
                nRedLeft, nBlueRight);
        t_ok('the helix draws in red', nRedLeft > 200);
        t_ok('the mesh triangle draws in blue', nBlueRight > 500);
        t_ok('no helix outside its plot', nnz(red(:, 321:640)) == 0);

        t_ok('PlotToPixels returns a pixel', isnumeric(pix) && numel(pix) == 2);
        if numel(pix) == 2
            px = round(pix);
            near = red(max(1, px(2) - 2):min(480, px(2) + 4), ...
                       max(1, px(1) - 2):min(640, px(1) + 4));
            fprintf('  helix point 100 maps to [%.1f %.1f]\n', pix);
            t_ok('PlotToPixels lands on the helix', any(near(:)));
        end

        ig = PsychImGuiFrame('Begin', ig);
        err = glGetError();
        PsychImGuiFrame('End', ig);
        t_ok('Render leaves GL_NO_ERROR', err == 0);

        PsychImGuiClose(ig);
        ig = [];
    catch e
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  test_gl_implot3d threw %s: %s\n', e.identifier, e.message);
    end

    PsychImGuiClose(ig);
    if ~isempty(win)
        sca;
    end
    clear prefGuard;
    fprintf('test_gl_implot3d: %d passed, %d failed\n', TST_PASS, TST_FAIL);
end
