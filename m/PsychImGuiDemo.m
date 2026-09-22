function PsychImGuiDemo(nFrames)
% PsychImGuiDemo  A Gabor patch with a PsychImGui control panel.
%
%   PsychImGuiDemo()          Run until you press ESCAPE or the Quit button.
%   PsychImGuiDemo(n)         Run n frames and return. Useful for a smoke run.
%
%   The demo opens a 640x480 Psychtoolbox window, draws a Gabor patch, and
%   draws a control panel over it. The sliders drive the contrast, the spatial
%   frequency, and the orientation of the patch. The contrast slider is the
%   Michelson contrast of the patch, from 0 to 1. A text field and the Dear
%   ImGui demo window are there to show the rest of the binding.
%
%   With ImPlot compiled in, a second panel shows a live trace of the contrast
%   over the last 512 frames and a heat map of the patch envelope.
%
%   The demo is also the shortest example of the four helpers: PsychImGuiOpen,
%   PsychImGuiFrame, PsychImGuiClose, and PsychImGuiGL. It writes no
%   Screen('BeginOpenGL') and Screen('EndOpenGL') pair of its own.
%
%   Needs Psychtoolbox. The demo opens with PsychDefaultSetup(2), so colors
%   are in the normalized 0 to 1 range, as in every Psychtoolbox demo. The
%   window preferences come from tests/gl/ptb_test_window, which skips the
%   display sync tests, so the demo starts fast. An experiment that measures
%   timing must not do that.
%
%   See also PsychImGuiOpen, PsychImGuiFrame, PsychImGuiClose, PsychImGuiGL.

    if nargin < 1
        nFrames = Inf;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(fullfile(root, 'tests', 'gl'));
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

        [win, rect] = ptb_test_window([0 0 640 480]); %#ok<ASGLU>

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

        hasImPlot = PsychImGui('Version').implot;
        trace = zeros(1, 512);
        [gx, gy] = meshgrid(linspace(-2, 2, 24), linspace(-2, 2, 24));

        % disableNorm = 1 and contrastPreMultiplicator = 0.5 make the
        % 'contrast' parameter below the Michelson contrast of the patch, which
        % is what a slider from 0 to 1 labelled "contrast" should mean. With
        % PTB's defaults the shader scales contrast by 1/(sqrt(2*pi)*sc), about
        % 1/125 for sc = 50, so 0.6 would draw an amplitude of 0.005 and the
        % patch would look like a plain gray square. See CreateProceduralGabor.
        gabor = CreateProceduralGabor(win, 256, 256, 0, [0.5 0.5 0.5 0], 1, 0.5);
        dst = CenterRectOnPoint([0 0 256 256], ig.rect(3) / 2, ig.rect(4) / 2);

        while running && frame < nFrames
            frame = frame + 1;

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
                gaborStd = gabor_std(win, dst);
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
                if PsychImGui('Button', 'Quit')
                    running = false;
                end
            end
            PsychImGui('End');

            if hasImPlot
                trace = [trace(2:end), contrast];
                envelope = exp(-(gx .^ 2 + gy .^ 2) / 2) .* contrast;
                PsychImGui('SetNextWindowPos', [310 10]);
                PsychImGui('SetNextWindowSize', [320 300]);
                if PsychImGui('Begin', 'Signals')
                    if PsychImGui('ImPlot.BeginPlot', 'contrast', [-1 120])
                        PsychImGui('ImPlot.SetupAxes', 'frame', 'contrast');
                        PsychImGui('ImPlot.SetupAxisLimits', 'ImAxis_Y1', 0, 1);
                        PsychImGui('ImPlot.PlotLine', 'trace', trace, ...
                                   'LineColor', [0.2 0.8 1 1], 'LineWeight', 2);
                        PsychImGui('ImPlot.EndPlot');
                    end
                    if PsychImGui('ImPlot.BeginPlot', 'envelope', [-1 130])
                        % The matrix goes to ImPlot column major, with no copy.
                        PsychImGui('ImPlot.PlotHeatmap', 'gabor', envelope, 0, 1, '');
                        PsychImGui('ImPlot.EndPlot');
                    end
                end
                PsychImGui('End');
            end

            if showDemo
                showDemo = PsychImGui('ShowDemoWindow', showDemo);
            end

            PsychImGuiFrame('End', ig);
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
