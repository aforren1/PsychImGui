function PsychImGuiDemo(nFrames, opts)
% PsychImGuiDemo  A Gabor patch with a PsychImGui control panel.
%
%   PsychImGuiDemo()          Run until you press ESCAPE or the Quit button.
%   PsychImGuiDemo(n)         Run n frames and return. Useful for a smoke run.
%   PsychImGuiDemo(n, opts)   The same, with options:
%
%       opts.rect      window rectangle, default [0 0 640 480]. The panels
%                      follow the window size.
%       opts.capture   a PNG file name. The last frame is written to it
%                      with Screen('GetImage') before the flip.
%       opts.animate   true to move the contrast along a slow sine, so the
%                      trace shows a signal without a hand on the slider.
%
%   tools/CaptureReadmeScreenshot uses both to make the README image.
%
%   The demo opens a Psychtoolbox window, draws a Gabor patch, and
%   draws a control panel over it. The sliders drive the contrast, the spatial
%   frequency, and the orientation of the patch. The contrast slider is the
%   Michelson contrast of the patch, from 0 to 1. A text field, a file
%   dialog, and the Dear ImGui demo window are there to show the rest of the
%   binding.
%
%   With ImPlot compiled in, a second panel shows a live trace of the contrast
%   over the last 512 frames and a heat map of the patch envelope. With
%   ImPlot3D compiled in, a third panel shows a simulated gaze trajectory in
%   3D above a surface of the patch envelope; drag it to rotate the box.
%
%   A third panel has two tabs. "Log" is a table of the slider values, one
%   row per half second. "Texture" shows a Psychtoolbox texture through
%   PsychImGui('Image'). An overlay drawn through the foreground draw list
%   marks the patch outline, its center, and its rotation angle; the
%   "overlay" check box turns it off.
%
%   The demo is also the shortest example of the four helpers: PsychImGuiOpen,
%   PsychImGuiFrame, PsychImGuiClose, and PsychImGuiGL. It writes no
%   Screen('BeginOpenGL') and Screen('EndOpenGL') pair of its own.
%
%   Needs Psychtoolbox. The demo opens with PsychDefaultSetup(2), so colors
%   are in the normalized 0 to 1 range, as in every Psychtoolbox demo. The
%   window preferences come from m/private/psychimgui_demo_window, which
%   skips the display sync tests, so the demo starts fast. An experiment that measures
%   timing must not do that.
%
%   See also PsychImGuiOpen, PsychImGuiFrame, PsychImGuiClose, PsychImGuiGL,
%   PsychImGuiImage.

    if nargin < 1 || isempty(nFrames)
        nFrames = Inf;
    end
    if nargin < 2 || isempty(opts)
        opts = struct();
    end
    winRect = [0 0 640 480];
    if isfield(opts, 'rect') && ~isempty(opts.rect)
        winRect = opts.rect;
    end
    captureFile = '';
    if isfield(opts, 'capture')
        captureFile = opts.capture;
    end
    animate = isfield(opts, 'animate') && ~isempty(opts.animate) && opts.animate;

    % The window and pixel helpers are in m/private, so the demo changes no
    % path. PsychImGuiSetup changes it only when it is not right yet. A path
    % change while the locked MEX is loaded crashes Octave 10.1 on Linux, and
    % a second run of the demo in one session would otherwise do that.
    PsychImGuiSetup();

    if exist('Screen', 'file') == 0
        error('psychimgui:NoPTB', ...
              'PsychImGuiDemo needs Psychtoolbox, which is not on the path.');
    end

    win = [];
    ig = [];
    try
        % The standard opening line of a Psychtoolbox script: AssertOpenGL,
        % KbName('UnifyKeyNames'), and the normalized 0 to 1 color range for
        % every window PsychImaging opens afterwards. The [0.5 0.5 0.5 0]
        % background offset of the Gabor below assumes that range. It has to
        % come before the window opens.
        PsychDefaultSetup(2);

        [win, rect] = psychimgui_demo_window(winRect);
        W = rect(3);
        H = rect(4);
        % Panel sizes follow the window, within limits that keep them usable
        % at 640x480 and not sparse at 1280x720.
        sideW = min(420, max(320, round(0.3 * W)));
        sigH = min(400, max(300, round(0.46 * H)));
        logH = min(220, max(140, round(0.26 * H)));

        ig = PsychImGuiOpen(win);
        PsychImGuiGL(ig, 'StyleColorsDark');
        PsychImGuiGL(ig, 'SetGlobalScale', 1.25);

        contrast = 0.6;
        freq = 0.03;
        orientation = 45;
        showDemo = false;
        label = 'trial 1';
        running = true;
        frame = 0;

        v = PsychImGuiGL(ig, 'Version');
        hasImPlot = v.implot;
        hasImPlot3D = v.implot3d;
        hasDialog = v.fileDialog;
        chosenFile = '';
        trace = contrast * ones(1, 512);
        [gx, gy] = meshgrid(linspace(-2, 2, 24), linspace(-2, 2, 24));
        % A gaze trace for the 3D panel: a slow drift with a fixational
        % tremor, in arbitrary screen units, with time on the third axis.
        [sx, sy] = meshgrid(linspace(-1, 1, 16), linspace(-1, 1, 16));

        % disableNorm = 1 and contrastPreMultiplicator = 0.5 make the
        % 'contrast' parameter below the Michelson contrast of the patch, which
        % is what a slider from 0 to 1 labelled "contrast" should mean. With
        % PTB's defaults the shader scales contrast by 1/(sqrt(2*pi)*sc), about
        % 1/125 for sc = 50, so 0.6 would draw an amplitude of 0.005 and the
        % patch would look like a plain gray square. See CreateProceduralGabor.
        gabor = CreateProceduralGabor(win, 256, 256, 0, [0.5 0.5 0.5 0], 1, 0.5);
        dst = CenterRectOnPoint([0 0 256 256], ig.rect(3) / 2, ig.rect(4) / 2);
        center = [(dst(1) + dst(3)) / 2, (dst(2) + dst(4)) / 2];

        % A texture for PsychImGui('Image'). specialFlags 1 makes it
        % GL_TEXTURE_2D, the only kind Dear ImGui's backends can sample; the
        % PTB default, GL_TEXTURE_RECTANGLE, raises psychimgui:Texture. uint8
        % keeps it an 8 bit texture under the normalized color range.
        [tx, ty] = meshgrid(linspace(-1, 1, 128), linspace(-1, 1, 64));
        thumb = uint8(255 * (0.5 + 0.5 * sin(12 * tx) .* exp(-3 * (tx .^ 2 + ty .^ 2))));
        thumb = repmat(thumb, [1 1 3]);
        thumb(1:8, 1:8, 2:3) = 0;    % a red corner shows which way is up
        thumbTex = Screen('MakeTexture', win, thumb, [], 1);
        thumbImg = PsychImGuiImage(ig, thumbTex);

        showOverlay = true;
        logRows = zeros(0, 4);       % [frame contrast frequency orientation]

        while running && frame < nFrames
            frame = frame + 1;
            if animate
                contrast = 0.55 + 0.35 * sin(frame / 12);
            end

            % The Gabor shader writes Offset + envelope * sine into every pixel
            % of its texture rectangle and puts 0 in alpha, so the rectangle is
            % an opaque 0.5 gray square where the envelope has faded. Alpha
            % blending cannot hide it (alpha is 0 everywhere). Clearing to the
            % same 0.5 gray, as ProceduralGaborDemo does, makes the edge of the
            % rectangle invisible and gives the patch a mean luminance surround.
            Screen('FillRect', win, 0.5);

            Screen('DrawTexture', win, gabor, [], dst, orientation, [], [], ...
                   [1 1 1 0], [], kPsychDontDoRotation, ...
                   [180, freq, 50, contrast, 1, 0, 0, 0]);

            if frame == 1
                % A procedural Gabor fails silently: wrong normalization draws
                % a flat gray square and raises nothing. Measure the first
                % frame instead of trusting it. Read the back buffer before the
                % flip, because after a flip its contents are undefined.
                gaborStd = psychimgui_gabor_std(win, dst);
                fprintf('PsychImGuiDemo: Gabor pixel std %.4f at contrast %.2f\n', ...
                        gaborStd, contrast);
                % Measured on the development machine: 0.0734 with these
                % parameters, 0.0021 with the normalization the demo used to
                % have, which is the flat gray square. 0.02 sits between them
                % with room on both sides. Contrast 1.0 only reaches 0.12, so a
                % higher bar would fail on a correct patch.
                if gaborStd < 0.02
                    error('psychimgui:FlatGabor', ...
                          ['The Gabor drew as a flat patch: pixel std %.4f, ' ...
                           'expected well above 0.02 at contrast %.2f. Check ' ...
                           'the CreateProceduralGabor normalization, and that ' ...
                           'PsychDefaultSetup(2) ran before the window ' ...
                           'opened.'], gaborStd, contrast);
                end
            end

            ig = PsychImGuiFrame('Begin', ig);

            PsychImGui('SetNextWindowPos', [10 10]);
            PsychImGui('SetNextWindowSize', [280 0]);
            if PsychImGui('Begin', 'Gabor controls')
                PsychImGui('Text', sprintf('frame %d', frame));
                [~, contrast] = PsychImGui('SliderFloat', 'contrast', contrast, 0, 1);
                [~, freq] = PsychImGui('SliderFloat', 'frequency', freq, 0.005, 0.2, '%.4f');
                [~, orientation] = PsychImGui('SliderFloat', 'orientation', ...
                                              orientation, 0, 180, '%.0f deg');
                PsychImGui('Separator');
                [~, label] = PsychImGui('InputText', 'label', label);
                [~, showDemo] = PsychImGui('Checkbox', 'Dear ImGui demo', showDemo);
                PsychImGui('SameLine');
                [~, showOverlay] = PsychImGui('Checkbox', 'overlay', showOverlay);
                if hasDialog && PsychImGui('Button', 'Open file...')
                    PsychImGui('FileDialog.Open', 'demoFile', 'Choose a file', ...
                               '.m,.png,.csv,.*', pwd);
                end
                if ~isempty(chosenFile)
                    [~, fname, fext] = fileparts(chosenFile);
                    PsychImGui('Text', ['file: ' fname fext]);
                end
                if PsychImGui('Button', 'Quit')
                    running = false;
                end
            end
            PsychImGui('End');

            if hasDialog && PsychImGui('FileDialog.Display', 'demoFile', [480 320])
                if PsychImGui('FileDialog.IsOk')
                    chosenFile = PsychImGui('FileDialog.GetFilePathName');
                end
                PsychImGui('FileDialog.Close');
            end

            if hasImPlot
                trace = [trace(2:end), contrast];
                envelope = exp(-(gx .^ 2 + gy .^ 2) / 2) .* contrast;
                PsychImGui('SetNextWindowPos', [W - sideW - 10, 10]);
                PsychImGui('SetNextWindowSize', [sideW, sigH]);
                if PsychImGui('Begin', 'Signals')
                    if PsychImGui('ImPlot.BeginPlot', 'contrast', [-1, (sigH - 60) / 2])
                        PsychImGui('ImPlot.SetupAxes', 'frame', 'contrast');
                        PsychImGui('ImPlot.SetupAxisLimits', 'ImAxis_Y1', 0, 1);
                        PsychImGui('ImPlot.PlotLine', 'trace', trace, ...
                                   'LineColor', [0.2 0.8 1 1], 'LineWeight', 2);
                        PsychImGui('ImPlot.EndPlot');
                    end
                    if PsychImGui('ImPlot.BeginPlot', 'envelope', [-1, (sigH - 60) / 2])
                        % The matrix goes to ImPlot column major, with no copy.
                        PsychImGui('ImPlot.PushColormap', 'Viridis');
                        PsychImGui('ImPlot.PlotHeatmap', 'gabor', envelope, 0, 1, '');
                        PsychImGui('ImPlot.PopColormap');
                        PsychImGui('ImPlot.EndPlot');
                    end
                end
                PsychImGui('End');
            end

            if hasImPlot3D
                % Positions come from the frame count, so the panel shows the
                % same picture on every run.
                tt = (frame - 1 + (1:240)) / 60;
                gazeX = 0.6 * sin(0.7 * tt) + 0.05 * sin(23 * tt);
                gazeY = 0.5 * cos(0.5 * tt) + 0.05 * cos(19 * tt);
                gazeZ = linspace(-1, 1, numel(tt));
                sz = 0.6 * contrast * exp(-2 * (sx .^ 2 + sy .^ 2)) - 1;
                PsychImGui('SetNextWindowPos', [W - sideW - 10, sigH + 20]);
                PsychImGui('SetNextWindowSize', [sideW, H - sigH - 30]);
                if PsychImGui('Begin', 'Gaze in 3D')
                    if PsychImGui('ImPlot3D.BeginPlot', 'gaze', [-1 -1], ...
                                  'ImPlot3DFlags_NoLegend')
                        PsychImGui('ImPlot3D.SetupAxes', 'x', 'y', 'time');
                        PsychImGui('ImPlot3D.SetupAxesLimits', -1, 1, -1, 1, -1, 1);
                        PsychImGui('ImPlot3D.PushColormap', 'Viridis');
                        PsychImGui('ImPlot3D.PlotSurface', 'envelope', sx, sy, sz);
                        PsychImGui('ImPlot3D.PopColormap');
                        PsychImGui('ImPlot3D.PlotLine', 'gaze', gazeX, gazeY, gazeZ, ...
                                   'LineColor', [1 0.85 0.2 1], 'LineWeight', 2);
                        PsychImGui('ImPlot3D.EndPlot');
                    end
                end
                PsychImGui('End');
            end

            if mod(frame, 30) == 1
                logRows = [logRows(max(1, end - 49):end, :); ...
                           frame, contrast, freq, orientation]; %#ok<AGROW>
            end
            PsychImGui('SetNextWindowPos', [10, H - logH - 10]);
            PsychImGui('SetNextWindowSize', [sideW - 30, logH]);
            if PsychImGui('Begin', 'Log and texture')
                if PsychImGui('BeginTabBar', 'tabs')
                    if PsychImGui('BeginTabItem', 'Log')
                        local_log_table(logRows);
                        PsychImGui('EndTabItem');
                    end
                    if PsychImGui('BeginTabItem', 'Texture')
                        PsychImGui('Image', thumbImg, thumbImg.size);
                        PsychImGui('SameLine');
                        PsychImGui('Text', sprintf('%d x %d\n%s', thumbImg.size, ...
                                                   thumbImg.orientation));
                        PsychImGui('EndTabItem');
                    end
                    PsychImGui('EndTabBar');
                end
            end
            PsychImGui('End');

            if showOverlay
                % The foreground draw list sits above every window. Its
                % handle is only good until PsychImGuiFrame('End'), so it is
                % fetched again every frame.
                fg = PsychImGui('GetForegroundDrawList');
                yellow = [1 0.85 0.2 0.9];
                PsychImGui('DrawList.AddRect', fg, dst(1:2), dst(3:4), yellow, 6, 2);
                PsychImGui('DrawList.AddLine', fg, center - [8 0], center + [8 0], yellow);
                PsychImGui('DrawList.AddLine', fg, center - [0 8], center + [0 8], yellow);
                % Screen('DrawTexture') rotates clockwise, and y points down.
                tip = center + 110 * [cosd(orientation), sind(orientation)];
                PsychImGui('DrawList.AddLine', fg, center, tip, yellow, 2);
                PsychImGui('DrawList.AddCircleFilled', fg, tip, 4, yellow);
                PsychImGui('DrawList.AddText', fg, dst(1:2) + [4 -18], yellow, ...
                           sprintf('%.0f deg', orientation));
            end

            if showDemo
                showDemo = PsychImGui('ShowDemoWindow', showDemo);
            end

            PsychImGuiFrame('End', ig);
            if ~isempty(captureFile) && frame == nFrames
                % Before the flip: afterwards the back buffer is undefined.
                imwrite(Screen('GetImage', win, [], 'backBuffer'), captureFile);
                fprintf('PsychImGuiDemo: wrote %s\n', captureFile);
            end
            Screen('Flip', win);

            % The GUI takes the keyboard while a text field is active, so the
            % experiment only reads keys when Dear ImGui does not want them.
            [~, wantKeyboard] = PsychImGui('WantCapture');
            if ~wantKeyboard && ~isempty(ig.in.keys)
                escCode = KbName('ESCAPE');
                if any(ig.in.keys(:, 1) == escCode & ig.in.keys(:, 2) == 1)
                    running = false;
                end
            end
            if isinf(nFrames) && ~ig.kq.active && KbCheck()
                running = false;   % no keyboard queue: fall back to KbCheck
            end
        end
    catch e
        fprintf(2, 'PsychImGuiDemo failed: %s: %s\n', e.identifier, e.message);
    end

    PsychImGuiClose(ig);
    if ~isempty(win)
        sca;
    end
end

function local_log_table(rows)
    flags = {'ImGuiTableFlags_Borders', 'ImGuiTableFlags_RowBg', ...
             'ImGuiTableFlags_ScrollY'};
    if ~PsychImGui('BeginTable', 'log', 4, flags)
        return;
    end
    PsychImGui('TableSetupColumn', 'frame');
    PsychImGui('TableSetupColumn', 'contrast');
    PsychImGui('TableSetupColumn', 'freq');
    PsychImGui('TableSetupColumn', 'deg');
    PsychImGui('TableSetupScrollFreeze', 0, 1);    % header stays in view
    PsychImGui('TableHeadersRow');
    % Newest first, so the latest values are visible without scrolling.
    for r = size(rows, 1):-1:1
        PsychImGui('TableNextRow');
        PsychImGui('TableNextColumn');
        PsychImGui('Text', sprintf('%d', rows(r, 1)));
        PsychImGui('TableNextColumn');
        PsychImGui('Text', sprintf('%.2f', rows(r, 2)));
        PsychImGui('TableNextColumn');
        PsychImGui('Text', sprintf('%.3f', rows(r, 3)));
        PsychImGui('TableNextColumn');
        PsychImGui('Text', sprintf('%.0f', rows(r, 4)));
    end
    PsychImGui('EndTable');
end
