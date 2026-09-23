function tex = PsychImGuiImage(ig, ptbTexture, filter)
% PsychImGuiImage  Prepare a Psychtoolbox texture for PsychImGui('Image').
%
%   tex = PsychImGuiImage(ig, ptbTexture)
%   tex = PsychImGuiImage(ig, ptbTexture, filter)
%
%   Returns a struct that PsychImGui('Image') and PsychImGui('ImageButton')
%   take in place of a texture:
%
%       img = rand(64, 128);
%       ptbTex = Screen('MakeTexture', win, img, [], 1);   % specialFlags 1
%       tex = PsychImGuiImage(ig, ptbTex);
%       ...
%       PsychImGui('Image', tex, [128 64]);                 % inside a frame
%
%   The texture must be a GL_TEXTURE_2D texture. Dear ImGui's OpenGL
%   backends bind and sample GL_TEXTURE_2D only, and Psychtoolbox makes
%   GL_TEXTURE_RECTANGLE textures unless Screen('MakeTexture') gets
%   specialFlags 1. Any other texture raises psychimgui:Texture.
%
%   filter is 'linear' (default) or 'nearest'. PsychImGui('Image') applies
%   it to every draw of tex. This call also sets it on the texture itself
%   once, through PsychImGui('SetTextureFilter'): Psychtoolbox creates a
%   texture with the OpenGL default minification filter, which needs mipmaps
%   the texture does not have, so the texture is incomplete and a conforming
%   driver samples it as black.
%
%   Fields of tex:
%
%       glId        OpenGL texture name
%       glTarget    OpenGL texture target, 3553 (GL_TEXTURE_2D)
%       size        [width height] in pixels
%       uvMap       [u0 v0 dudx dvdx dudy dvdy], the map from image
%                   coordinates, 0 to 1 from the top left corner, to texture
%                   coordinates. PsychImGui('Image') uses it so the image
%                   shows upright.
%       orientation 'transposed' for a texture made from a matrix, 'upright'
%                   for one stored bottom row first, as an offscreen window
%       filter      'linear' or 'nearest'
%       ptbTexture  the Psychtoolbox texture handle
%
%   ig is the handle from PsychImGuiOpen, or a bare window handle. Call this
%   once per texture, outside a frame or inside it: it enters the OpenGL
%   context for the filter through PsychImGuiGL, which nests safely. The
%   texture name stays valid until Screen('Close', ptbTexture); after that,
%   drawing tex is undefined.
%
%   See also PsychImGui, PsychImGuiGL, PsychImGuiOpen.

    if nargin < 2
        error('psychimgui:Usage', 'PsychImGuiImage(ig, ptbTexture [, filter])');
    end
    if nargin < 3 || isempty(filter)
        filter = 'linear';
    end
    if ~ischar(filter) || ~any(strcmp(filter, {'linear', 'nearest'}))
        error('psychimgui:Usage', ...
              'PsychImGuiImage: filter must be ''linear'' or ''nearest''.');
    end
    if isstruct(ig) && isfield(ig, 'win')
        win = ig.win;
    elseif isnumeric(ig) && isscalar(ig)
        win = ig;
    else
        error('psychimgui:Usage', ...
              'PsychImGuiImage: the first argument must be a PsychImGuiOpen handle.');
    end
    if ~isnumeric(ptbTexture) || ~isscalar(ptbTexture)
        error('psychimgui:Type', ...
              'PsychImGuiImage: ptbTexture must be one Psychtoolbox texture handle.');
    end

    kGlTexture2D = 3553;          % GL_TEXTURE_2D
    kGlTextureRectangle = 34037;  % GL_TEXTURE_RECTANGLE

    [glId, glTarget] = Screen('GetOpenGLTexture', win, ptbTexture);
    if glTarget ~= kGlTexture2D
        if glTarget == kGlTextureRectangle
            what = 'a GL_TEXTURE_RECTANGLE texture, the Psychtoolbox default';
        else
            what = sprintf('a texture with target 0x%04X', glTarget);
        end
        error('psychimgui:Texture', ...
              ['Psychtoolbox texture %d is %s. Dear ImGui samples GL_TEXTURE_2D ' ...
               'only. Create it with specialFlags 1: ' ...
               'Screen(''MakeTexture'', win, img, [], 1).'], ptbTexture, what);
    end

    % Screen('GetOpenGLTexture') maps an image position to texture coordinates
    % with the texture's own orientation. The top image row lands near v = 0
    % for a texture made from a matrix, which PTB stores transposed, and near
    % v = 1 for one stored bottom row first. PTB reports the orientation
    % nowhere else.
    [~, ~, ~, vTop] = Screen('GetOpenGLTexture', win, ptbTexture, 0, 0);
    rect = Screen('Rect', ptbTexture);

    if vTop > 0.25
        orientation = 'upright';
        uvMap = [0 1 1 0 0 -1];     % u = x, v = 1 - y
    else
        orientation = 'transposed';
        uvMap = [0 0 0 1 1 0];      % u = y, v = x
    end

    tex = struct('glId', glId, 'glTarget', glTarget, ...
                 'size', [rect(3) - rect(1), rect(4) - rect(2)], ...
                 'uvMap', uvMap, 'orientation', orientation, ...
                 'filter', filter, 'ptbTexture', ptbTexture);

    PsychImGuiGL(ig, 'SetTextureFilter', glId, filter);
end
