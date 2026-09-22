function test_keymap()
% TEST_KEYMAP  Shape of the PTB keycode table and a few known entries.

    map = PsychImGuiKeymap();
    t_isa('keymap class', map, 'int32');
    t_ok('keymap shape', isequal(size(map), [256 1]));

    keyA = PsychImGui('Enum', 'ImGuiKey_A');
    keyLeft = PsychImGui('Enum', 'ImGuiKey_LeftArrow');
    keyShift = PsychImGui('Enum', 'ImGuiKey_LeftShift');

    t_ok('some keys are mapped', sum(map ~= 0) > 40);
    t_ok('letter A is mapped once or more', any(map == keyA));
    t_ok('LeftArrow is mapped', any(map == keyLeft));
    t_ok('LeftShift is mapped', any(map == keyShift));

    % Every non-zero entry must be a key Dear ImGui knows, never a stray value.
    e = PsychImGui('Enum');
    known = [];
    f = fieldnames(e);
    for i = 1:numel(f)
        if strncmp(f{i}, 'ImGuiKey_', 9)
            known(end + 1) = e.(f{i}); %#ok<AGROW>
        end
    end
    t_ok('all mapped values are ImGuiKey values', all(ismember(double(map(map ~= 0)), known)));

    % Unknown PTB names map to 0, which NewFrame ignores.
    t_ok('unmapped entries stay zero', any(map == 0));
end
