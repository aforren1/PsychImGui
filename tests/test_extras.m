function test_extras()
% TEST_EXTRAS  The hand-written widget and plot subcommands (SPEC.md 14.15).
%
%   Headless: textures are bare GL names, which the none renderer never
%   samples, so these tests check the argument rules and the results, not the
%   pixels.

    %% frame and plot rules
    t_throws('SliderDouble outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('SliderDouble', 's', 0.5, 0, 1));
    t_throws('PlotBarGroups outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.PlotBarGroups', {'a'}, 1));

    section_begin();

    %% double precision widgets
    v = [0.123456789012345 2 3];
    [changed, out] = PsychImGui('SliderDouble', 'sd', v, 0, 10);
    t_ok('SliderDouble keeps double precision', isequal(out, v) && ~changed);
    [~, out] = PsychImGui('SliderDouble', 'sd1', 0.25, 0, 1, '%.6f', 'ImGuiSliderFlags_AlwaysClamp');
    t_eq('SliderDouble with one component', out, 0.25);
    [changed, out] = PsychImGui('DragDouble', 'dd', 1e-9);
    t_ok('DragDouble keeps a tiny value', out == 1e-9 && islogical(changed));
    [~, out] = PsychImGui('DragDouble', 'dd4', [1 2 3 4], 0.1, 0, 10);
    t_eq('DragDouble with four components', out, [1 2 3 4]);
    t_throws('SliderDouble refuses single', 'psychimgui:Type', ...
             @() PsychImGui('SliderDouble', 'x', single(1), 0, 1));
    t_throws('DragDouble refuses 17 components', 'psychimgui:Type', ...
             @() PsychImGui('DragDouble', 'x', zeros(1, 17)));
    t_throws('SliderDouble refuses a string format', 'psychimgui:Usage', ...
             @() PsychImGui('SliderDouble', 'x', 1, 0, 2, '%s'));
    t_throws('DragDouble refuses two conversions', 'psychimgui:Usage', ...
             @() PsychImGui('DragDouble', 'x', 1, 1, 0, 2, '%f %f'));
    [~, out] = PsychImGui('DragDouble', 'pct', 50, 1, 0, 100, '%.0f %%');
    t_eq('a literal percent sign is fine', out, 50);
    t_throws('SliderDouble needs a range', 'psychimgui:Usage', ...
             @() PsychImGui('SliderDouble', 'x', 1));

    section_end();
    section_begin();
    %% table sort specs
    t_throws('TableGetSortSpecs outside a table', 'psychimgui:Usage', ...
             @() PsychImGui('TableGetSortSpecs'));
    if PsychImGui('BeginTable', 'plain', 2)
        PsychImGui('TableSetupColumn', 'a');
        PsychImGui('TableSetupColumn', 'b');
        [s, dirty] = PsychImGui('TableGetSortSpecs');
        t_ok('a table without Sortable has no specs', isempty(s) && isstruct(s) && ~dirty);
        PsychImGui('EndTable');
    else
        t_ok('table plain opened', false);
    end
    if PsychImGui('BeginTable', 'sorted', 2, 'ImGuiTableFlags_Sortable')
        PsychImGui('TableSetupColumn', 'a');
        PsychImGui('TableSetupColumn', 'b', 'ImGuiTableColumnFlags_DefaultSort');
        PsychImGui('TableHeadersRow');
        [s, dirty] = PsychImGui('TableGetSortSpecs');
        t_ok('the default sort is one spec', numel(s) == 1 && dirty);
        if numel(s) == 1
            t_eq('the default sort column', s.columnIndex, 1);
            t_ok('the direction is a word for sort', any(strcmp(s.direction, {'ascend', 'descend'})));
            t_eq('sort accepts the direction', sort([3 1 2], s.direction), sort([3 1 2], s.direction));
        end
        [~, dirty] = PsychImGui('TableGetSortSpecs');
        t_ok('reading the specs clears dirty', ~dirty);
        PsychImGui('EndTable');
    else
        t_ok('table sorted opened', false);
    end

    section_end();
    section_begin();
    %% ImPlot items
    tex = 1;
    transposed = struct('glId', 1, 'glTarget', 3553, 'uvMap', [0 0 0 1 1 0]);
    t_throws('PlotBarGroups outside a plot', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.PlotBarGroups', {'a'}, 1));
    t_throws('PlotImage outside a plot', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.PlotImage', 'img', tex, [0 0], [1 1]));
    if PsychImGui('ImPlot.BeginPlot', 'items', [300 200])
        PsychImGui('ImPlot.PlotBarGroups', {'left', 'right'}, [1 2; 3 4; 5 6]);
        PsychImGui('ImPlot.PlotBarGroups', {'left', 'right'}, int32([1 2; 3 4]), 0.5, 0.1, ...
                   'Flags', 'ImPlotBarGroupsFlags_Stacked');
        t_ok('PlotBarGroups with one label per column', true);
        t_throws('PlotBarGroups with too few labels', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot.PlotBarGroups', {'only'}, [1 2; 3 4]));
        PsychImGui('ImPlot.PlotPieChart', {'a', 'b', 'c'}, [1 2 3], 0.5, 0.5, 0.4);
        PsychImGui('ImPlot.PlotPieChart', {'a', 'b'}, single([1 1]), 0.5, 0.5, 0.2, [], 0);
        t_ok('PlotPieChart with and without labels', true);
        t_throws('PlotPieChart refuses an integer format', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot.PlotPieChart', {'a'}, 1, 0, 0, 1, '%d'));
        t_throws('PlotPieChart with too many labels', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot.PlotPieChart', {'a', 'b'}, 1, 0, 0, 1));
        PsychImGui('ImPlot.PlotImage', 'upright', tex, [0 0], [1 1]);
        PsychImGui('ImPlot.PlotImage', 'turned', transposed, [1 1], [2 2], [0 0], [1 1], ...
                   [1 1 1 0.5]);
        t_ok('PlotImage upright and transposed', true);
        t_throws('PlotImage with a rectangle texture', 'psychimgui:Texture', ...
                 @() PsychImGui('ImPlot.PlotImage', 'r', ...
                                struct('glId', 1, 'glTarget', 34037), [0 0], [1 1]));
        PsychImGui('ImPlot.EndPlot');
    else
        t_ok('plot items opened', false);
    end

    section_end();
    section_begin();
    %% ImPlot3D image
    t_throws('ImPlot3D PlotImage outside a plot', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot3D.PlotImage', 'img', tex, zeros(4, 3)));
    if PsychImGui('ImPlot3D.BeginPlot', 'img3', [300 200])
        corners = [0 1 1; 1 1 1; 1 0 0; 0 0 0];
        PsychImGui('ImPlot3D.PlotImage', 'upright', tex, corners);
        PsychImGui('ImPlot3D.PlotImage', 'turned', transposed, corners, [1 0 0 1]);
        t_ok('ImPlot3D PlotImage upright and transposed', true);
        t_throws('ImPlot3D PlotImage needs 4x3 corners', 'psychimgui:Type', ...
                 @() PsychImGui('ImPlot3D.PlotImage', 'x', tex, zeros(3, 4)));
        PsychImGui('ImPlot3D.EndPlot');
    else
        t_ok('plot img3 opened', false);
    end

    section_end();
    section_begin();
    %% subplots
    t_throws('EndSubplots without BeginSubplots', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.EndSubplots'));
    t_throws('IsSubplotsHovered outside subplots', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.IsSubplotsHovered'));
    if PsychImGui('ImPlot.BeginSubplots', 'grid', 1, 2, [400 200])
        t_isa('IsSubplotsHovered inside subplots', ...
              PsychImGui('ImPlot.IsSubplotsHovered'), 'logical');
        PsychImGui('ImPlot.EndSubplots');
    else
        t_ok('subplots grid opened', false);
    end

    section_end();
    section_begin();
    %% axis links
    t_throws('AxisLink of an unknown key', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.AxisLink', 'test_extras_none'));
    t_eq('AxisLink sets a range', PsychImGui('ImPlot.AxisLink', 'test_extras_x', [2 5]), [2 5]);
    for k = 1:2
        if PsychImGui('ImPlot.BeginPlot', sprintf('linked%d', k), [300 150])
            PsychImGui('ImPlot.SetupAxisLinks', 'ImAxis_X1', 'test_extras_x');
            PsychImGui('ImPlot.PlotLine', 'l', [0 10], [0 1]);
            lim = PsychImGui('ImPlot.GetPlotLimits');
            t_ok(sprintf('plot %d takes the linked x range', k), ...
                 abs(lim(1) - 2) < 1e-9 && abs(lim(2) - 5) < 1e-9);
            PsychImGui('ImPlot.EndPlot');
        else
            t_ok(sprintf('plot linked%d opened', k), false);
        end
    end
    t_throws('SetupAxisLinks outside a plot', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.SetupAxisLinks', 'ImAxis_X1', 'test_extras_x'));
    t_throws('a link key that is too long', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.AxisLink', repmat('k', 1, 48), [0 1]));
    t_throws('SetNextAxisLinks with a bad axis', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot.SetNextAxisLinks', 7, 'test_extras_x'));
    PsychImGui('ImPlot.SetNextAxisLinks', 'ImAxis_Y1', 'test_extras_y');
    if PsychImGui('ImPlot.BeginPlot', 'nextlinked', [300 150])
        PsychImGui('ImPlot.EndPlot');
    end
    t_eq('SetNextAxisLinks makes a link with the default range', ...
         numel(PsychImGui('ImPlot.AxisLink', 'test_extras_y')), 2);

    section_end();
end

function section_begin()
    PsychImGui('NewFrame', tf_input());
    PsychImGui('SetNextWindowPos', [0 0]);
    PsychImGui('SetNextWindowSize', [640 480]);
    PsychImGui('Begin', 'extras', [], 0);
end

function section_end()
    PsychImGui('End');
    PsychImGui('Render');
end
