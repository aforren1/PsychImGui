function test_dispatch()
% TEST_DISPATCH  Name lookup, opcode fast path, and the lifecycle errors.

    PsychImGui('Shutdown');
    km = zeros(256, 1, 'int32');
    opts = struct('renderer', 'none', 'iniFile', '');

    %% before Init
    t_throws('widget before Init', 'psychimgui:NotInit', ...
             @() PsychImGui('Button', 'x'));
    t_throws('NewFrame before Init', 'psychimgui:NotInit', ...
             @() PsychImGui('NewFrame', tf_input()));

    %% unknown names and opcodes
    t_throws('unknown name', 'psychimgui:UnknownCommand', @() PsychImGui('Frobnicate'));
    t_throws('opcode out of range', 'psychimgui:UnknownCommand', @() PsychImGui(1e6));
    t_throws('negative opcode', 'psychimgui:UnknownCommand', @() PsychImGui(-1));
    t_throws('bad selector class', 'psychimgui:Usage', @() PsychImGui({'Button'}));

    %% these work without Init
    v = PsychImGui('Version');
    t_ok('Version is a struct', isstruct(v) && isfield(v, 'imgui'));
    t_ok('Version imguiNum', isnumeric(v.imguiNum) && v.imguiNum > 19000);
    e = PsychImGui('Enum', 'ImGuiWindowFlags_NoTitleBar');
    t_eq('Enum NoTitleBar', e, 1);
    t_throws('Enum unknown', 'psychimgui:UnknownCommand', ...
             @() PsychImGui('Enum', 'ImGuiNotAThing'));
    allEnums = PsychImGui('Enum');
    t_ok('Enum table is a struct', isstruct(allEnums) && ...
         isfield(allEnums, 'ImGuiKey_A'));

    %% Init and the AlreadyInit guard
    PsychImGui('Init', 0, [0 0 640 480], km, opts);
    t_ok('Init sets renderer none', strcmp(PsychImGui('Version').renderer, 'none'));
    t_throws('Init twice', 'psychimgui:AlreadyInit', ...
             @() PsychImGui('Init', 0, [0 0 640 480], km, opts));

    %% argument count checks
    t_throws('Button with no label', 'psychimgui:Usage', @() PsychImGui('Button'));
    t_throws('Button with too many args', 'psychimgui:Usage', ...
             @() PsychImGui('Button', 'x', [0 0], 1, 2));
    t_throws('End with an argument', 'psychimgui:Usage', @() PsychImGui('End', 1));
    t_throws('Button label is numeric', 'psychimgui:Type', @() PsychImGui('Button', 7));

    %% opcode fast path agrees with the name path
    op = PsychImGuiOp();
    t_eq('Opcode(Button) matches the table', PsychImGui('Opcode', 'Button'), op.Button);
    t_throws('Opcode of an unknown name', 'psychimgui:UnknownCommand', ...
             @() PsychImGui('Opcode', 'Frobnicate'));

    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'dispatch');
    byName = PsychImGui('Button', 'same');
    byOpcode = PsychImGui(op.Button, 'same');
    t_eq('name and opcode agree', byName, byOpcode);
    t_isa('Button returns logical', byName, 'logical');
    PsychImGui('End');
    PsychImGui('Render');

    %% flags accept numbers, names, and cellstr
    PsychImGui('NewFrame', tf_input());
    numericFlag = PsychImGui('Enum', 'ImGuiWindowFlags_NoTitleBar') + ...
                  PsychImGui('Enum', 'ImGuiWindowFlags_NoResize');
    PsychImGui('Begin', 'w1', [], numericFlag);
    PsychImGui('End');
    PsychImGui('Begin', 'w2', [], 'ImGuiWindowFlags_NoTitleBar');
    PsychImGui('End');
    PsychImGui('Begin', 'w3', [], {'ImGuiWindowFlags_NoTitleBar', ...
                                   'ImGuiWindowFlags_NoResize'});
    PsychImGui('End');
    t_ok('flags by number, name, and cellstr', true);
    t_throws('unknown flag name', 'psychimgui:Usage', ...
             @() PsychImGui('Begin', 'w4', [], 'ImGuiWindowFlags_Nope'));
    PsychImGui('Render');

    %% Shutdown is idempotent
    PsychImGui('Shutdown');
    PsychImGui('Shutdown');
    t_ok('Shutdown twice is safe', true);
    t_throws('widget after Shutdown', 'psychimgui:NotInit', ...
             @() PsychImGui('Button', 'x'));
end
