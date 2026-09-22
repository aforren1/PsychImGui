function test_assert()
% TEST_ASSERT  An IM_ASSERT inside Dear ImGui becomes psychimgui:ImGuiAssert,
% and the next frame still works.
%
%   The stock IM_ASSERT calls abort(), which would take the whole MATLAB
%   process down. Section 8.3 redirects it to a deferred error instead.

    PsychImGui('NewFrame', tf_input());
    t_throws('End without Begin', 'psychimgui:ImGuiAssert', @() PsychImGui('End'));

    % Error recovery is enabled, so the context is still usable. Close the
    % frame and start a clean one.
    try
        PsychImGui('Render');
    catch
        % A recovery path may raise once more; the next frame is what matters.
    end

    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'after assert');
    pressed = PsychImGui('Button', 'still works');
    PsychImGui('End');
    PsychImGui('Render');
    t_isa('frame after an assert still runs', pressed, 'logical');

    % A second, unrelated assert must also be reported rather than swallowed.
    PsychImGui('NewFrame', tf_input());
    t_throws('PopID without PushID', 'psychimgui:ImGuiAssert', @() PsychImGui('PopID'));
    try
        PsychImGui('Render');
    catch
    end
    t_ok('assert state does not leak into the next call', true);
end
