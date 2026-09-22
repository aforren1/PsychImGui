function s = gabor_std(win, dst)
% GABOR_STD  Standard deviation of the pixels in one rectangle, 0 to 1.
%
%   s = gabor_std(win, dst)
%
%   Reads the back buffer of window win inside rectangle dst and returns the
%   standard deviation of its pixel values, scaled to 0 to 1. A Gabor patch
%   with any useful contrast gives a value well above zero; a flat gray square
%   gives about zero.
%
%   This exists because a procedural Gabor fails silently. With PTB's default
%   disableNorm = 0 the shader scales the contrast by 1/(sqrt(2*pi)*sc), which
%   is about 1/125 for sc = 50, so a contrast of 0.6 becomes an amplitude of
%   0.005 and the patch looks like a plain gray square. Nothing errors. Both
%   PsychImGuiDemo and tests/gl/test_gl_demo_gabor measure the result instead
%   of trusting it.
%
%   Read the back buffer before Screen('Flip'), not after: after a flip the
%   back buffer holds undefined contents.
%
%   See also PsychImGuiDemo, test_gl_demo_gabor.

    img = Screen('GetImage', win, dst, 'backBuffer');
    v = double(img(:));
    if max(v) > 1.5
        v = v / 255;    % GetImage returns uint8 unless asked for float
    end
    s = std(v);
end
