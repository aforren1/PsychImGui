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

    %% widgets and window queries need a frame
    % Dear ImGui has no current window outside NewFrame to Render, and these
    % crashed the host before the dispatcher checked for a frame.
    t_throws('Button outside a frame', 'psychimgui:Usage', @() PsychImGui('Button', 'x'));
    t_throws('GetWindowPos outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('GetWindowPos'));
    t_throws('ImPlot.BeginPlot outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.BeginPlot', 'x'));
    t_ok('input queries work outside a frame', ...
         ~PsychImGui('IsKeyDown', 'ImGuiKey_A') && numel(PsychImGui('GetMousePos')) == 2);
    t_ok('colormaps work outside a frame', PsychImGui('ImPlot.GetColormapCount') > 0);
    ini = PsychImGui('SaveIniSettingsToMemory');
    PsychImGui('LoadIniSettingsFromMemory', ini);
    t_ok('ini settings round trip outside a frame', ischar(ini));

    %% argument count checks
    PsychImGui('NewFrame', tf_input());
    t_throws('Button with no label', 'psychimgui:Usage', @() PsychImGui('Button'));
    t_throws('Button with too many args', 'psychimgui:Usage', ...
             @() PsychImGui('Button', 'x', [0 0], 1, 2));
    t_throws('End with an argument', 'psychimgui:Usage', @() PsychImGui('End', 1));
    t_throws('Button label is numeric', 'psychimgui:Type', @() PsychImGui('Button', 7));
    PsychImGui('Render');

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

    %% index enums are range checked before they reach the library
    % IM_ASSERT returns (SPEC.md 8.3), so without these checks each call
    % below would index past an array inside Dear ImGui or ImPlot.
    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'axes', [], 0);
    t_throws('ImGuiCol past the end', 'psychimgui:Range', ...
             @() PsychImGui('PushStyleColor', 63, [1 0 0 1]));
    t_throws('ImGuiStyleVar negative', 'psychimgui:Range', ...
             @() PsychImGui('PushStyleVar', -1, 1));
    t_throws('ImGuiKey_None is not a key', 'psychimgui:Range', ...
             @() PsychImGui('IsKeyDown', 0));
    t_throws('two modifiers are not one key', 'psychimgui:Range', ...
             @() PsychImGui('IsKeyDown', {'ImGuiMod_Ctrl', 'ImGuiMod_Shift'}));
    t_ok('a named key and a modifier pass', ...
         ~PsychImGui('IsKeyDown', 'ImGuiKey_A') && ~PsychImGui('IsKeyDown', 'ImGuiMod_Ctrl'));
    t_throws('ImPlotColormap past the count', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot.PushColormapIndex', PsychImGui('ImPlot.GetColormapCount')));
    t_throws('ImPlotColormap auto where it has no meaning', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot.GetColormapName', -1));
    c = PsychImGui('ImPlot.SampleColormap', 0.5, -1);
    t_ok('ImPlotColormap auto where it is the default', numel(c) == 4);
    t_throws('GetColormapColor negative idx', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot.GetColormapColor', -1));
    t_throws('ImPlot3D GetColormapColor negative idx', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot3D.GetColormapColor', -1));
    t_throws('a chord of two modifiers and no key', 'psychimgui:Range', ...
             @() PsychImGui('IsKeyChordPressed', {'ImGuiMod_Ctrl', 'ImGuiMod_Shift'}));
    t_throws('a chord below the named keys', 'psychimgui:Range', ...
             @() PsychImGui('Shortcut', 5));
    t_ok('a chord of a key and modifiers passes', ...
         ~PsychImGui('IsKeyChordPressed', {'ImGuiMod_Ctrl', 'ImGuiMod_Shift', 'ImGuiKey_S'}));
    t_throws('EndPlot without BeginPlot', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.EndPlot'));
    t_throws('ImPlot3D EndPlot without BeginPlot', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot3D.EndPlot'));
    dl = PsychImGui('GetWindowDrawList');
    t_throws('a curve with no current point', 'psychimgui:Usage', ...
             @() PsychImGui('DrawList.PathBezierQuadraticCurveTo', dl, [5 5], [10 0]));
    t_throws('table column query outside a table', 'psychimgui:Usage', ...
             @() PsychImGui('TableGetColumnFlags', 0));
    if PsychImGui('BeginTable', 'cols', 2)
        t_throws('table column -1 before the first cell', 'psychimgui:Range', ...
                 @() PsychImGui('TableGetColumnName'));
        PsychImGui('TableNextRow');
        PsychImGui('TableNextColumn');
        t_throws('table column past the last', 'psychimgui:Range', ...
                 @() PsychImGui('TableGetColumnFlags', 2));
        t_ok('table column -1 in a cell', ischar(PsychImGui('TableGetColumnName')));
        PsychImGui('EndTable');
    end

    if PsychImGui('ImPlot.BeginPlot', 'y2', [300 200])
        t_throws('ImAxis past Y3', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.SetupAxis', 6));
        t_throws('ImAxis negative', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.SetupAxisLimits', -1, 0, 1));
        t_throws('ImPlotScale past SymLog', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.SetupAxisScale', 'ImAxis_X1', 4));
        PsychImGui('ImPlot.SetupAxis', 'ImAxis_Y2', 'right', 'ImPlotAxisFlags_Opposite');
        PsychImGui('ImPlot.PlotLine', 'left', [0 1 2], [0 1 0]);
        PsychImGui('ImPlot.SetAxes', 'ImAxis_X1', 'ImAxis_Y2');
        PsychImGui('ImPlot.PlotLine', 'right', [0 1 2], [0 100 0]);
        PsychImGui('ImPlot.SetAxis', 'ImAxis_Y1');
        p = PsychImGui('ImPlot.GetPlotMousePos', -1, -1);
        t_ok('ImAxis -1 where IMPLOT_AUTO is the default', numel(p) == 2);
        PsychImGui('ImPlot.EndPlot');
        t_ok('items on Y1 and Y2 of one plot', true);
    end
    if PsychImGui('ImPlot3D.BeginPlot', 'pick', [300 200])
        [o, d] = PsychImGui('ImPlot3D.PixelsToPlotRay', 150, 100);
        q = PsychImGui('ImPlot3D.PixelsToPlotPlane', 150, 100, 'ImPlane3D_XY');
        t_ok('PixelsToPlotRay gives an origin and a direction', ...
             isequal(size(o), [1 3]) && isequal(size(d), [1 3]));
        t_ok('PixelsToPlotPlane gives a point', isequal(size(q), [1 3]));
        PsychImGui('ImPlot3D.EndPlot');
    end
    PsychImGui('End');
    PsychImGui('Render');

    %% numeric formats are checked before they reach snprintf
    % A '%s' read the slider's value as a char pointer and crashed the host.
    PsychImGui('NewFrame', tf_input());
    PsychImGui('SetNextWindowPos', [0 0]);
    PsychImGui('SetNextWindowSize', [640 480]);
    PsychImGui('Begin', 'formats', [], 0);
    t_throws('SliderFloat refuses %s', 'psychimgui:Usage', ...
             @() PsychImGui('SliderFloat', 'f', 0.5, 0, 1, '%s'));
    t_throws('SliderInt refuses a float conversion', 'psychimgui:Usage', ...
             @() PsychImGui('SliderInt', 'i', 1, 0, 9, '%.2f'));
    t_throws('DragFloatRange2 checks formatMax', 'psychimgui:Usage', ...
             @() PsychImGui('DragFloatRange2', 'r', 0, 1, 1, 0, 1, '%.1f', '%n'));
    [~, v] = PsychImGui('SliderInt', 'i2', 3, 0, 9, 'trial %d of 9');
    [~, w] = PsychImGui('SliderFloat', 'f2', 0.5, 0, 1, '%5.1f %%');
    t_ok('text around one conversion is fine', v == 3 && abs(w - 0.5) < 1e-6);
    [~, w] = PsychImGui('SliderFloat', 'f3', 0.5, 0, 1, 'gain');
    t_ok('a format without a conversion is fine', abs(w - 0.5) < 1e-6);
    if PsychImGui('ImPlot.BeginPlot', 'fmtplot', [200 150])
        t_throws('SetupAxisFormat refuses %s', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot.SetupAxisFormat', 'ImAxis_X1', '%s'));
        t_throws('PlotHeatmap refuses %d', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot.PlotHeatmap', 'h', magic(3), 0, 0, '%d'));
        PsychImGui('ImPlot.EndPlot');
    else
        t_ok('fmtplot opened', false);
    end
    PsychImGui('End');
    PsychImGui('Render');

    %% Shutdown is idempotent
    PsychImGui('Shutdown');
    PsychImGui('Shutdown');
    t_ok('Shutdown twice is safe', true);
    t_throws('widget after Shutdown', 'psychimgui:NotInit', ...
             @() PsychImGui('Button', 'x'));
end
