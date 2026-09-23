function test_image()
% TEST_IMAGE  Image, ImageButton, SetTextureFilter, and PsychImGuiImage,
% without a GPU.
%
%   The none renderer never samples a texture, so this checks the argument
%   rules and the texture descriptor. tests/gl/test_gl_phase2 checks the
%   pixels.

    % A transposed PTB texture, as PsychImGuiImage describes one.
    tex = struct('glId', 7, 'glTarget', 3553, 'size', [64 32], ...
                 'uvMap', [0 0 0 1 1 0]);

    for f = 1:2
        PsychImGui('NewFrame', tf_input());
        PsychImGui('Begin', 'img');
        PsychImGui('Image', 7, [64 32]);
        PsychImGui('Image', 7, [64 32], [0 0], [0.5 1], [0 0 0 1], [1 1 1 0.5]);
        PsychImGui('Image', tex, [64 32]);
        PsychImGui('Image', tex, [64 32], [], [], [0.2 0.2 0.2 1]);
        upright = tex;
        upright.uvMap = [0 1 1 0 0 -1];
        PsychImGui('Image', upright, [64 32], [0.25 0.25], [0.75 0.75]);
        pressed = PsychImGui('ImageButton', 'b1', 7, [16 16]);
        pressed2 = PsychImGui('ImageButton', 'b2', tex, [16 16], [0 0], [1 1], ...
                              [0 0 0 1], [1 0 0 1]);
        PsychImGui('End');
        PsychImGui('Render');
    end
    t_isa('ImageButton returns logical', pressed, 'logical');
    t_isa('ImageButton with a descriptor returns logical', pressed2, 'logical');
    t_ok('Image draws with a name and with a descriptor', true);

    %% argument checks
    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'img');
    rect = tex;
    rect.glTarget = 34037;
    t_throws('a rectangle texture is refused', 'psychimgui:Texture', ...
             @() PsychImGui('Image', rect, [64 32]));
    t_throws('a rectangle texture is refused by ImageButton', 'psychimgui:Texture', ...
             @() PsychImGui('ImageButton', 'b', rect, [64 32]));
    t_throws('texture name 0 is refused', 'psychimgui:Texture', ...
             @() PsychImGui('Image', 0, [64 32]));
    t_throws('a fractional texture name is refused', 'psychimgui:Texture', ...
             @() PsychImGui('Image', 1.5, [64 32]));
    t_throws('a char texture is refused', 'psychimgui:Type', ...
             @() PsychImGui('Image', 'tex', [64 32]));
    t_throws('a struct without glTarget is refused', 'psychimgui:Type', ...
             @() PsychImGui('Image', struct('glId', 7), [64 32]));
    bad = tex;
    bad.filter = 'cubic';
    t_throws('an unknown descriptor filter is refused', 'psychimgui:Usage', ...
             @() PsychImGui('Image', bad, [64 32]));
    bad = tex;
    bad.uvMap = [0 0 1];
    t_throws('a short uvMap is refused', 'psychimgui:Type', ...
             @() PsychImGui('Image', bad, [64 32]));
    t_throws('size must have two elements', 'psychimgui:Type', ...
             @() PsychImGui('Image', 7, 64));
    t_throws('a 1x3 tint is refused', 'psychimgui:Type', ...
             @() PsychImGui('Image', 7, [64 32], [0 0], [1 1], [0 0 0 0], [1 1 1]));
    t_throws('Image with no size', 'psychimgui:Usage', @() PsychImGui('Image', 7));
    t_throws('ImageButton needs a char id', 'psychimgui:Type', ...
             @() PsychImGui('ImageButton', 3, 7, [16 16]));
    PsychImGui('End');
    PsychImGui('Render');
    t_throws('Image outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('Image', 7, [64 32]));

    %% SetTextureFilter, which is a no-op without a renderer
    PsychImGui('SetTextureFilter', 7);
    PsychImGui('SetTextureFilter', tex, 'nearest');
    t_ok('SetTextureFilter takes a name or a descriptor', true);
    t_throws('SetTextureFilter checks the mode', 'psychimgui:Usage', ...
             @() PsychImGui('SetTextureFilter', 7, 'cubic'));
    t_throws('SetTextureFilter checks the target', 'psychimgui:Texture', ...
             @() PsychImGui('SetTextureFilter', rect));

    %% PsychImGuiImage against the recording Screen stub
    if ~tf_screen('active')
        t_ok('the Screen stub is on the path (run this file through run_tests)', false);
        return;
    end
    tf_screen('reset');
    d = PsychImGuiImage(11, 21);
    t_eq('descriptor glId', d.glId, 121);
    t_eq('descriptor glTarget', d.glTarget, 3553);
    t_eq('descriptor size', d.size, [64 32]);
    t_eq('a matrix texture is transposed', d.orientation, 'transposed');
    t_eq('the transposed map', d.uvMap, [0 0 0 1 1 0]);
    t_eq('the filter call ran in one GL region', tf_screen('gl'), ...
         {'BeginOpenGL', 'EndOpenGL'});
    u = PsychImGuiImage(11, 23, 'nearest');
    t_eq('an offscreen texture is upright', u.orientation, 'upright');
    t_eq('the upright map', u.uvMap, [0 1 1 0 0 -1]);
    t_throws('PsychImGuiImage refuses a rectangle texture', 'psychimgui:Texture', ...
             @() PsychImGuiImage(11, 22));
    t_eq('the descriptor keeps the filter', u.filter, 'nearest');
    t_throws('PsychImGuiImage checks the filter', 'psychimgui:Usage', ...
             @() PsychImGuiImage(11, 21, 'cubic'));
    t_eq('a refused call left 2D mode', tf_screen('mode'), 0);
    t_throws('PsychImGuiImage needs a texture', 'psychimgui:Usage', ...
             @() PsychImGuiImage(11));

    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'img');
    PsychImGui('Image', d, d.size);
    PsychImGui('Image', u, u.size);
    PsychImGui('ImageButton', 'near', u, [16 16]);
    PsychImGui('End');
    PsychImGui('Render');
    t_ok('Image takes the PsychImGuiImage descriptor', true);

    % test_helpers reads the recorded region calls from a clean list.
    tf_screen('reset');
end
