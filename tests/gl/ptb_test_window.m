function [win, rect, cleanupPrefs] = ptb_test_window(sizeRect, stereoMode, screenid)
% PTB_TEST_WINDOW  Open a small Psychtoolbox window for a test or a demo.
%
%   [win, rect] = ptb_test_window()            640x480 at the top left corner
%   [win, rect] = ptb_test_window([x y w h])   a rectangle of your own
%   [win, rect] = ptb_test_window('full')      the whole screen
%   [win, rect] = ptb_test_window(r, stereoMode)   a Psychtoolbox stereo mode
%   [win, rect] = ptb_test_window(r, m, screenid)  on a given screen, for
%                                                  example 0 on Windows to
%                                                  span every display
%
%   rect is Screen('Rect', win), which in a stereo mode that splits the
%   window, such as mode 4, is the rectangle of one eye.
%
%   The function sets two preferences before opening the window:
%
%       Screen('Preference', 'SkipSyncTests', 2)
%       Screen('Preference', 'VisualDebugLevel', 0)
%
%   SkipSyncTests = 2 skips the display timing calibration, which takes
%   seconds on every launch and fails on a windowed test window anyway.
%   VisualDebugLevel = 0 removes the startup splash screen. Neither belongs in
%   a real experiment, where timing has to be verified, so they live here in
%   the test helper instead of in the binding.
%
%   The third output is an onCleanup object that restores both preferences.
%   Keep it alive for as long as the window is open.
%
%   Every script in this project that opens a window calls this function, so
%   the preferences are set in one place.

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
