function [win, rect, cleanupPrefs] = psychimgui_demo_window(sizeRect, stereoMode, screenid)
% PSYCHIMGUI_DEMO_WINDOW  Open the Psychtoolbox window of a demo.
%
%   [win, rect] = psychimgui_demo_window()            640x480 at the top left
%   [win, rect] = psychimgui_demo_window([x y w h])   a rectangle of your own
%   [win, rect] = psychimgui_demo_window('full')      the whole screen
%   [win, rect] = psychimgui_demo_window(r, stereoMode)   a stereo mode
%   [win, rect] = psychimgui_demo_window(r, m, screenid)  on a given screen
%
%   The demos' copy of tests/gl/ptb_test_window. It lives in m/private so the
%   shipped demos find it without an addpath: a shipped function that changes
%   the path while the locked MEX is loaded crashes Octave 10.1 on Linux, and
%   a demo that runs twice in one session would do that (SPEC.md sections
%   14.6 and 14.12). The test copy stays in tests/gl for the GL tests.
%
%   It sets SkipSyncTests to 2 and VisualDebugLevel to 0 before it opens the
%   window, so a demo starts fast. Neither belongs in a real experiment. The
%   third output restores both preferences; keep it alive while the window is
%   open.

    if nargin < 1 || isempty(sizeRect)
        sizeRect = [0 0 640 480];
    elseif ischar(sizeRect) && strcmp(sizeRect, 'full')
        sizeRect = [];
    end
    if nargin < 2 || isempty(stereoMode)
        stereoMode = 0;
    end

    oldSync = Screen('Preference', 'SkipSyncTests', 2);
    oldDebug = Screen('Preference', 'VisualDebugLevel', 0);
    cleanupPrefs = onCleanup(@() restorePrefs(oldSync, oldDebug));

    % Screen('BeginOpenGL') refuses to run without this.
    InitializeMatlabOpenGL(1);

    if nargin < 3 || isempty(screenid)
        screenid = max(Screen('Screens'));
    end
    [win, rect] = PsychImaging('OpenWindow', screenid, 0, sizeRect, [], [], stereoMode);
end

function restorePrefs(oldSync, oldDebug)
    try
        Screen('Preference', 'SkipSyncTests', oldSync);
        Screen('Preference', 'VisualDebugLevel', oldDebug);
    catch
        % Screen may already be unloaded; the preferences go with it.
    end
end
