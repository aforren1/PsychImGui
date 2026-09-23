function PsychImGuiStereoDemo(stereoMode, nFrames, winRect)
% PsychImGuiStereoDemo  A PsychImGui panel in both eyes of a stereo display.
%
%   PsychImGuiStereoDemo()            Pick the stereo mode from the displays.
%   PsychImGuiStereoDemo(mode)        Use a Psychtoolbox stereo mode.
%   PsychImGuiStereoDemo(mode, n)     Run n frames and return.
%   PsychImGuiStereoDemo(mode, n, r)  In a window with rectangle r, or
%                                     'full' for the whole screen.
%
%   With two or more displays the demo uses stereo mode 4, one window split
%   across the displays, left eye on the left display. With one display it
%   falls back to mode 8, red-blue anaglyph; look through red-blue glasses.
%   Mode 10, one window per display, works too when the displays are
%   separate Psychtoolbox screens: PsychImGuiStereoDemo(10).
%
%   Each eye shows a disc inside a frame, shifted left or right by half the
%   disparity, so the disc floats in front of or behind the frame. The
%   control panel sets the disparity and is drawn into both eyes at zero
%   disparity, so it sits in the plane of the screen.
%
%   The pattern for a stereo script:
%
%       ig = PsychImGuiOpen(win);                 % ig.stereo is true
%       for eye = 0:1
%           Screen('SelectStereoDrawBuffer', win, eye);
%           ... draw that eye's stimulus ...
%       end
%       ig = PsychImGuiFrame('Begin', ig);        % input for the frame, once
%       ... PsychImGui widgets, once ...
%       PsychImGuiFrame('End', ig);               % Render into eye 0,
%                                                 % RenderAgain into eye 1
%       Screen('Flip', win);
%
%   The mouse position is in window coordinates. In mode 4 the left display
%   is the left eye, so the panel responds to the mouse there.
%
%   Needs Psychtoolbox. The window preferences come from
%   tests/gl/ptb_test_window, which skips the display sync tests; an
%   experiment that measures timing must not do that.
%
%   See also PsychImGuiDemo, PsychImGuiFrame, PsychImGuiOpen.

    if nargin < 2 || isempty(nFrames)
        nFrames = Inf;
    end
    if nargin < 3
        winRect = [];
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(fullfile(root, 'tests', 'gl'));
    PsychImGuiSetup();
    if exist('Screen', 'file') == 0
        error('psychimgui:NoPTB', ...
              'PsychImGuiStereoDemo needs Psychtoolbox, which is not on the path.');
    end

    if nargin < 1 || isempty(stereoMode)
        stereoMode = local_pick_mode();
    end
    if isempty(winRect)
        if stereoMode == 8
            winRect = [0 0 800 600];
        else
            % Modes 4 and 10 put one eye on each display.
            winRect = 'full';
        end
    end
    fprintf('PsychImGuiStereoDemo: stereo mode %d\n', stereoMode);

    win = [];
    ig = [];
    try
        PsychDefaultSetup(2);
        screenid = [];
        if stereoMode == 10
            % The left eye on the first display, the right eye in a window
            % of its own on the second, as in ImagingStereoDemo.
            [screenid, slave] = local_dual_screens();
            PsychImaging('PrepareConfiguration');
            PsychImaging('AddTask', 'General', 'DualWindowStereo', slave);
        elseif stereoMode == 4 && IsWin
            % Screen 0 is the whole desktop on Windows, so one window spans
            % both displays and each eye gets one of them.
            screenid = 0;
        end
        [win, rect] = ptb_test_window(winRect, stereoMode, screenid);
        ig = PsychImGuiOpen(win);
        if ~ig.stereo
            error('psychimgui:Usage', 'Stereo mode %d gave a mono window.', stereoMode);
        end

        disparity = 12;
        discSize = 80;
        running = true;
        frame = 0;
        [cx, cy] = RectCenter(rect);
        while running && frame < nFrames
            frame = frame + 1;
            for eye = 0:1
                Screen('SelectStereoDrawBuffer', win, eye);
                Screen('FillRect', win, 0.5);
                shift = (2 * eye - 1) * disparity / 2;
                Screen('FrameRect', win, 0, CenterRectOnPoint([0 0 300 300], cx, cy), 4);
                Screen('FillOval', win, 1, ...
                       CenterRectOnPoint([0 0 discSize discSize], cx + shift, cy));
            end

            ig = PsychImGuiFrame('Begin', ig);
            PsychImGui('SetNextWindowPos', [10 10]);
            PsychImGui('SetNextWindowSize', [280 0]);
            if PsychImGui('Begin', 'Stereo controls')
                PsychImGui('Text', sprintf('mode %d, frame %d', stereoMode, frame));
                [~, disparity] = PsychImGui('SliderFloat', 'disparity (px)', ...
                                            disparity, -40, 40, '%.0f');
                [~, discSize] = PsychImGui('SliderFloat', 'disc (px)', discSize, 20, 200, ...
                                           '%.0f');
                if PsychImGui('Button', 'Quit')
                    running = false;
                end
            end
            PsychImGui('End');
            PsychImGuiFrame('End', ig);
            Screen('Flip', win);

            [~, wantKeyboard] = PsychImGui('WantCapture');
            if ~wantKeyboard && ~isempty(ig.in.keys)
                if any(ig.in.keys(:, 1) == KbName('ESCAPE') & ig.in.keys(:, 2) == 1)
                    running = false;
                end
            end
            if isinf(nFrames) && ~ig.kq.active && KbCheck()
                running = false;
            end
        end
    catch e
        fprintf(2, 'PsychImGuiStereoDemo failed: %s: %s\n', e.identifier, e.message);
    end

    PsychImGuiClose(ig);
    if ~isempty(win)
        sca;
    end
end

function mode = local_pick_mode()
    % On Windows, screen 0 is the whole desktop and 1 to N are the displays;
    % elsewhere each screen is a display or an X screen.
    screens = Screen('Screens');
    if IsWin
        nDisplays = max(0, numel(screens) - 1);
    else
        nDisplays = numel(screens);
    end
    if nDisplays >= 2
        mode = 4;
    else
        mode = 8;
    end
end

function [master, slave] = local_dual_screens()
    if IsWin
        master = 1;
        slave = 2;
    else
        master = 0;
        slave = 1;
    end
end
