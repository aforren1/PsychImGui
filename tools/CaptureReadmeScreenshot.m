function file = CaptureReadmeScreenshot(file)
% CaptureReadmeScreenshot  Make the README screenshot again from the demo.
%
%   CaptureReadmeScreenshot()        writes docs/images/psychimgui-demo.png
%   CaptureReadmeScreenshot(file)    writes file instead
%
%   Runs PsychImGuiDemo in a 1280x720 window for 520 frames, with the
%   contrast moving along a slow sine so the ImPlot trace fills, and
%   writes the last frame with Screen('GetImage') before its flip. The window
%   comes from tests/gl/ptb_test_window, which skips the sync tests and the
%   splash screen. Run it after a change to the demo or the look of the GUI:
%
%       cd tools; CaptureReadmeScreenshot
%
%   Needs MATLAB or Octave with Psychtoolbox, a GPU, and a built MEX.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 1 || isempty(file)
        file = fullfile(root, 'docs', 'images', 'psychimgui-demo.png');
    end
    outdir = fileparts(file);
    if ~isempty(outdir) && ~exist(outdir, 'dir')
        mkdir(outdir);
    end

    addpath(fullfile(root, 'm'));
    PsychImGuiDemo(520, struct('rect', [0 0 1280 720], 'capture', file, ...
                               'animate', true));

    info = dir(file);
    if isempty(info)
        error('psychimgui:Capture', 'The demo did not write %s.', file);
    end
    fprintf('CaptureReadmeScreenshot: %s, %.0f KB\n', file, info.bytes / 1024);
end
