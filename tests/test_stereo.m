function test_stereo()
% TEST_STEREO  The Render and RenderAgain split, with renderer 'none'.
%
%   A stereo mode draws the same GUI into two eye buffers. Render builds the
%   draw data once and submits it; RenderAgain submits the same draw data
%   again and is legal only between a Render and the next NewFrame. The pixel
%   side, that both eyes really show the panel, is tests/gl/test_gl_stereo.

    t_throws('RenderAgain before any frame', 'psychimgui:Usage', ...
             @() PsychImGui('RenderAgain'));

    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'stereo');
    PsychImGui('Button', 'both eyes');
    PsychImGui('End');
    t_throws('RenderAgain inside the frame, before Render', 'psychimgui:Usage', ...
             @() PsychImGui('RenderAgain'));
    PsychImGui('Render');
    frame = PsychImGui('GetFrameCount');
    PsychImGui('RenderAgain');
    t_ok('RenderAgain after Render', true);
    PsychImGui('RenderAgain');
    t_ok('RenderAgain more than once', true);
    t_eq('RenderAgain builds no new frame', PsychImGui('GetFrameCount'), frame);
    t_throws('RenderAgain takes no arguments', 'psychimgui:Usage', ...
             @() PsychImGui('RenderAgain', 1));

    % The next NewFrame starts a frame whose draw data does not exist yet.
    PsychImGui('NewFrame', tf_input());
    t_throws('RenderAgain after the next NewFrame', 'psychimgui:Usage', ...
             @() PsychImGui('RenderAgain'));
    PsychImGui('EndFrame');
    t_throws('RenderAgain after EndFrame', 'psychimgui:Usage', ...
             @() PsychImGui('RenderAgain'));

    % Input goes to the frame once: a second submission does not advance
    % Dear ImGui's clock or its frame count.
    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'stereo');
    PsychImGui('End');
    PsychImGui('Render');
    t0 = PsychImGui('GetTime');
    PsychImGui('RenderAgain');
    t_eq('RenderAgain leaves the clock alone', PsychImGui('GetTime'), t0);

    s = PsychImGui('Stats');
    t_ok('Stats counts RenderAgain', any(strcmp({s.perOp.name}, 'RenderAgain')));

    op = PsychImGuiOp();
    t_ok('RenderAgain has an opcode', isfield(op, 'RenderAgain'));
    PsychImGui('Shutdown');
    t_throws('RenderAgain after Shutdown', 'psychimgui:NotInit', ...
             @() PsychImGui('RenderAgain'));
end
