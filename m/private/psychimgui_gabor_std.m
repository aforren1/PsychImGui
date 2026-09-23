function s = psychimgui_gabor_std(win, dst)
% PSYCHIMGUI_GABOR_STD  Standard deviation of the pixels in one rectangle, 0 to 1.
%
%   s = psychimgui_gabor_std(win, dst)
%
%   The demo's copy of tests/gl/gabor_std, in m/private so the shipped demo
%   needs no addpath (see psychimgui_demo_window). Reads the back buffer of
%   window win inside rectangle dst. A Gabor patch with any useful contrast
%   gives a value well above zero; a flat gray square gives about zero.
%
%   A procedural Gabor fails silently. With PTB's default disableNorm = 0 the
%   shader scales the contrast by 1/(sqrt(2*pi)*sc), about 1/125 for sc = 50,
%   so the patch looks like a plain gray square and nothing errors.
%
%   Read the back buffer before Screen('Flip'), not after: after a flip the
%   back buffer holds undefined contents.

    img = Screen('GetImage', win, dst, 'backBuffer');
    v = double(img(:));
    if max(v) > 1.5
        v = v / 255;    % GetImage returns uint8 unless asked for float
    end
    s = std(v);
end
