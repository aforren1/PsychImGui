function PsychImGuiDemo(nFrames)
% PsychImGuiDemo  A Gabor patch with a PsychImGui control panel.
%
%   PsychImGuiDemo()          Run until you press ESCAPE or close the panel.
%   PsychImGuiDemo(n)         Run n frames and return. Useful for a smoke run.
%
%   The demo opens a 640x480 Psychtoolbox window, draws a Gabor patch, and
%   draws a control panel over it. The sliders drive the contrast, the spatial
%   frequency, and the orientation of the patch. A text field and the Dear
%   ImGui demo window are there to show the rest of the binding.
%
%   With ImPlot compiled in, a second panel shows a live trace of the contrast
%   over the last 512 frames and a heat map of the patch envelope.
%
%   Needs Psychtoolbox. The window preferences come from
%   tests/gl/ptb_test_window, which skips the display sync tests, so the demo
%   starts fast. An experiment that measures timing must not do that.
%
%   See also PsychImGui, PsychImGuiInput, PsychImGuiFrame, PsychImGuiKeymap.

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
    kq = [];
    try
        [win, rect] = ptb_test_window([0 0 640 480]); %#ok<ASGLU>

        Screen('BeginOpenGL', win);
        PsychImGui('Init', win, rect, PsychImGuiKeymap());
        PsychImGui('StyleColorsDark');
        PsychImGui('SetGlobalScale', 1.25);
        Screen('EndOpenGL', win);

        kq = PsychImGuiInput('Start', win);

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

        gabor = CreateProceduralGabor(win, 256, 256, 0, [0.5 0.5 0.5 0.0]);
        cx = rect(3) / 2;
        cy = rect(4) / 2;
        dst = CenterRectOnPoint([0 0 256 256], cx, cy);

        while running && frame < nFrames
            frame = frame + 1;

            Screen('DrawTexture', win, gabor, [], dst, orientation, [], [], ...
                   [], [], kPsychDontDoRotation, ...
                   [180, freq, 50, contrast, 1, 0, 0, 0]);

            in = PsychImGuiFrame('Begin', win, kq);

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

            PsychImGuiFrame('End', win);
            Screen('Flip', win);

            % The GUI takes the keyboard while a text field is active, so the
            % experiment only reads keys when Dear ImGui does not want them.
            [~, wantKeyboard] = PsychImGui('WantCapture');
            if ~wantKeyboard && ~isempty(in.keys)
                escCode = KbName('ESCAPE');
                if any(in.keys(:, 1) == escCode & in.keys(:, 2) == 1)
                    running = false;
                end
            end
            if isinf(nFrames) && ~kq.active && KbCheck()
                running = false;   % no keyboard queue: fall back to KbCheck
            end
        end
    catch e
        fprintf(2, 'PsychImGuiDemo failed: %s: %s\n', e.identifier, e.message);
    end

    try
        if ~isempty(win)
            Screen('BeginOpenGL', win);
            PsychImGui('Shutdown');
            Screen('EndOpenGL', win);
        else
            PsychImGui('Shutdown');
        end
    catch
        PsychImGui('Shutdown');
    end
    if ~isempty(kq)
        PsychImGuiInput('Stop', kq);
    end
    sca;
end
