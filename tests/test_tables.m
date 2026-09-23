function test_tables()
% TEST_TABLES  Table call sequences, and the checks that keep a misplaced
% table call from crashing.
%
%   Dear ImGui guards several table functions with an IM_ASSERT and then
%   dereferences the current table anyway. The deferred assert returns, so
%   the binding checks those preconditions itself and raises instead.

    flags = {'ImGuiTableFlags_Borders', 'ImGuiTableFlags_RowBg', ...
             'ImGuiTableFlags_ScrollY'};

    % Dear ImGui hides a window on the frame it first appears, and a table in
    % a hidden window does not open, so run a few frames and test the last.
    for f = 1:3
        PsychImGui('NewFrame', tf_input());
        PsychImGui('SetNextWindowSize', [400 300]);
        PsychImGui('Begin', 'tables');
        open = PsychImGui('BeginTable', 'grid', 3, flags, [0 200]);
        if f == 3
            t_isa('BeginTable returns logical', open, 'logical');
            t_ok('BeginTable opens in a visible window', open);
        end
        if open
            PsychImGui('TableSetupColumn', 'name');
            PsychImGui('TableSetupColumn', 'value', 'ImGuiTableColumnFlags_WidthFixed', 80);
            PsychImGui('TableSetupColumn', 'unit');
            PsychImGui('TableSetupScrollFreeze', 0, 1);
            PsychImGui('TableHeadersRow');
            count = PsychImGui('TableGetColumnCount');
            for r = 1:4
                PsychImGui('TableNextRow');
                for c = 0:2
                    visible = PsychImGui('TableNextColumn');
                    idx = PsychImGui('TableGetColumnIndex');
                    if f == 3 && r == 1
                        t_isa(sprintf('TableNextColumn %d is logical', c), visible, 'logical');
                        t_eq(sprintf('column index %d', c), idx, c);
                    end
                    PsychImGui('Text', sprintf('r%d c%d', r, c));
                end
                PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_RowBg0', [0.2 0.2 0.4 1]);
                PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_CellBg', [1 0 0 1], 1);
            end
            % TableSetColumnIndex jumps back into a column of the current row.
            PsychImGui('TableNextRow', 0, 24);
            onScreen = PsychImGui('TableSetColumnIndex', 2);
            PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_CellBg', 4278190335);
            PsychImGui('TableHeader', 'manual');
            PsychImGui('EndTable');
            if f == 3
                t_eq('TableGetColumnCount', count, 3);
                t_isa('TableSetColumnIndex returns logical', onScreen, 'logical');
            end
        end
        PsychImGui('End');
        PsychImGui('Render');
    end

    %% outside a table the binding refuses the calls that would crash
    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'tables');
    t_throws('TableNextRow outside a table', 'psychimgui:Usage', ...
             @() PsychImGui('TableNextRow'));
    t_throws('TableHeader outside a table', 'psychimgui:Usage', ...
             @() PsychImGui('TableHeader', 'x'));
    t_throws('TableSetBgColor outside a table', 'psychimgui:Usage', ...
             @() PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_RowBg0', [1 0 0 1]));
    t_eq('TableGetColumnCount outside a table', PsychImGui('TableGetColumnCount'), 0);
    t_eq('TableNextColumn outside a table', PsychImGui('TableNextColumn'), false);
    t_throws('TableSetColumnIndex outside a table', 'psychimgui:Usage', ...
             @() PsychImGui('TableSetColumnIndex', 0));
    t_throws('BeginTable with 0 columns', 'psychimgui:Range', ...
             @() PsychImGui('BeginTable', 'bad', 0));
    t_throws('BeginTable with 512 columns', 'psychimgui:Range', ...
             @() PsychImGui('BeginTable', 'bad', 512));

    if PsychImGui('BeginTable', 'checks', 2)
        t_throws('TableHeader before a cell', 'psychimgui:Usage', ...
                 @() PsychImGui('TableHeader', 'x'));
        t_throws('TableSetColumnIndex before the first row', 'psychimgui:Usage', ...
                 @() PsychImGui('TableSetColumnIndex', 0));
        PsychImGui('TableNextRow');
        t_throws('TableSetColumnIndex out of range', 'psychimgui:Range', ...
                 @() PsychImGui('TableSetColumnIndex', 2));
        t_throws('TableSetBgColor target None', 'psychimgui:Usage', ...
                 @() PsychImGui('TableSetBgColor', 0, [1 0 0 1]));
        t_throws('TableSetBgColor column out of range', 'psychimgui:Range', ...
                 @() PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_CellBg', ...
                                [1 0 0 1], 2));
        t_throws('TableSetBgColor cell with no current cell', 'psychimgui:Usage', ...
                 @() PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_CellBg', [1 0 0 1]));
        t_throws('TableSetBgColor color of the wrong size', 'psychimgui:Type', ...
                 @() PsychImGui('TableSetBgColor', 'ImGuiTableBgTarget_RowBg0', [1 0 0]));
        PsychImGui('TableNextColumn');
        PsychImGui('Text', 'still fine');
        PsychImGui('EndTable');
        t_ok('the table works after the refused calls', true);
    else
        t_ok('BeginTable opened for the checks', false);
    end
    PsychImGui('End');
    PsychImGui('Render');
end
