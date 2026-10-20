function test_safety()
% TEST_SAFETY  Inputs that crashed the host before SPEC.md section 14.18.
%
%   Each call below reached an IM_ASSERT that returns (SPEC.md 8.3) and then
%   an out of bounds read or write inside Dear ImGui, ImPlot, or ImPlot3D.
%   A regression here ends the MATLAB session instead of failing one check.

    %% outside a frame
    t_throws('BustColorCache with a title needs a frame', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.BustColorCache', 'p'));

    %% colormaps
    section_begin();
    PsychImGui('ImPlot.BustColorCache', 'p');
    t_ok('BustColorCache with a title in a frame', true);
    n2 = PsychImGui('ImPlot.GetColormapCount');
    n3 = PsychImGui('ImPlot3D.GetColormapCount');
    t_throws('ImPlot.AddColormap with no colors', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.AddColormap', 'safetyEmpty', zeros(0, 4)));
    t_throws('ImPlot.AddColormap with one color', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.AddColormap', 'safetyOne', [1 0 0 1]));
    t_throws('ImPlot.AddColormap with a taken name', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.AddColormap', 'Viridis', [1 0 0 1; 0 1 0 1]));
    t_throws('ImPlot3D.AddColormap with no colors', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot3D.AddColormap', 'safetyEmpty', zeros(0, 4)));
    t_ok('a refused AddColormap adds nothing', ...
         PsychImGui('ImPlot.GetColormapCount') == n2 && ...
         PsychImGui('ImPlot3D.GetColormapCount') == n3);
    t_throws('ImPlot.PushColormap of an unknown name', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.PushColormap', 'nope'));
    t_throws('ImPlot3D.PushColormap of an unknown name', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot3D.PushColormap', 'nope'));
    t_throws('SampleColormap of NaN', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot.SampleColormap', NaN, 4));
    t_throws('ImPlot3D.SampleColormap of NaN', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot3D.SampleColormap', NaN, 4));
    t_eq('SampleColormap clamps t above 1', PsychImGui('ImPlot.SampleColormap', 1e9, 4), ...
         PsychImGui('ImPlot.SampleColormap', 1, 4));
    t_eq('ImPlot3D.SampleColormap clamps t below 0', ...
         PsychImGui('ImPlot3D.SampleColormap', -5, 4), PsychImGui('ImPlot3D.SampleColormap', 0, 4));
    t_throws('ColormapSlider at NaN', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot.ColormapSlider', 'cs', NaN, '', 4));
    PsychImGui('PushStyleVarVec2', 'ImGuiStyleVar_ButtonTextAlign', [5 0.5]);
    t_throws('ColormapButton with ButtonTextAlign.x past 1', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.ColormapButton', 'cb', [100 20], 4));
    PsychImGui('PopStyleVar');
    t_isa('ColormapButton with a normal style', ...
          PsychImGui('ImPlot.ColormapButton', 'cb', [100 20], 4), 'logical');
    section_end();

    %% formats
    section_begin();
    t_throws('a precision of 200 digits', 'psychimgui:Usage', ...
             @() PsychImGui('SliderFloat', 's', 0.5, 0, 1, ['%.' repmat('0', 1, 200) '3f']));
    t_throws('a width of 4 digits', 'psychimgui:Usage', ...
             @() PsychImGui('SliderInt', 'i', 1, 0, 9, '%1000d'));
    t_throws('6 flags', 'psychimgui:Usage', ...
             @() PsychImGui('DragFloat', 'd', 1, 1, 0, 2, '%------f'));
    [~, v] = PsychImGui('SliderFloat', 's2', 0.5, 0, 1, '%+08.3f');
    t_ok('flags, a width, and a precision within the limits', abs(v - 0.5) < 1e-6);
    section_end();

    %% plot data
    section_begin();
    if PsychImGui('ImPlot.BeginPlot', 'data', [400 300])
        t_throws('PlotPieChart with a negative value', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.PlotPieChart', {'a', 'b'}, [3 -2.5], .5, .5, .4));
        t_throws('PlotPieChart with a negative int8', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.PlotPieChart', {'a', 'b'}, int8([10 -8]), .5, .5, .4));
        t_throws('PlotPieChart with NaN', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.PlotPieChart', {'a', 'b'}, [1 NaN], .5, .5, .4));
        t_throws('PlotPieChart with Inf', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.PlotPieChart', {'a', 'b'}, [1 Inf], .5, .5, .4));
        PsychImGui('ImPlot.PlotPieChart', {'a', 'b'}, [0 2], .5, .5, .4);
        t_ok('PlotPieChart with a zero', true);
        PsychImGui('ImPlot.PushColormapIndex', 4);
        t_throws('PlotHeatmap with NaN', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.PlotHeatmap', 'h', [1 NaN; 2 3]));
        t_throws('PlotHeatmap with Inf', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.PlotHeatmap', 'h', single([1 Inf; 2 3])));
        PsychImGui('ImPlot.PlotHeatmap', 'h', int16([1 2; 3 4]));
        PsychImGui('ImPlot.PopColormap');
        PsychImGui('ImPlot.PlotLine', 'k', 1:10, 'Stride', 1e8);
        PsychImGui('ImPlot.PlotLine', 'k2', 1:10, 1:10, 'Stride', 3, 'Offset', -7);
        PsychImGui('ImPlot.PlotScatter', 'k3', int32(1:10), 'Offset', 1e6);
        t_ok('Stride and Offset stay inside the data', true);
        t_throws('a Stride of 0', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot.PlotLine', 'z', 1:4, 'Stride', 0));
        t_throws('PlotHeatmap refuses Stride', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot.PlotHeatmap', 'h', magic(3), 'Stride', 2));
        t_throws('PlotBarGroups refuses Offset', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot.PlotBarGroups', {'a'}, [1; 2], 'Offset', 1));
        PsychImGui('ImPlot.EndPlot');
    else
        t_ok('plot data opened', false);
    end
    section_end();

    section_begin();
    if PsychImGui('ImPlot3D.BeginPlot', 'data3', [400 300])
        PsychImGui('ImPlot3D.PushColormapIndex', 4);
        [X, Y] = meshgrid(1:3, 1:3);
        Z = X .* Y;
        Z(2, 2) = NaN;
        t_throws('PlotSurface with NaN', 'psychimgui:Range', ...
                 @() PsychImGui('ImPlot3D.PlotSurface', 's', X, Y, Z));
        PsychImGui('ImPlot3D.PopColormap');
        t_throws('PlotMesh refuses Offset', 'psychimgui:Usage', ...
                 @() PsychImGui('ImPlot3D.PlotMesh', 'm', [0 1 0], [0 0 1], [0 0 0], [1 2 3], ...
                                'Offset', 1));
        PsychImGui('ImPlot3D.PlotLine', 'l', 1:6, 1:6, 1:6, 'Stride', 2, 'Offset', -1);
        t_ok('ImPlot3D Stride and Offset stay inside the data', true);
        PsychImGui('ImPlot3D.EndPlot');
    else
        t_ok('plot data3 opened', false);
    end
    section_end();

    %% styles that fail every NewFrame
    bad = {struct('WindowMenuButtonPosition', 'ImGuiDir_Up'), ...
           struct('ColorButtonPosition', 'ImGuiDir_None'), ...
           struct('TreeLinesFlags', {{'ImGuiTreeNodeFlags_DrawLinesFull', ...
                                      'ImGuiTreeNodeFlags_DrawLinesToNodes'}}), ...
           struct('Alpha', 2), struct('CurveTessellationMaxError', 0), ...
           struct('CircleTessellationMaxError', -1), struct('WindowMinSize', [0 5]), ...
           struct('WindowBorderHoverPadding', 0), struct('ButtonTextAlign', [1e9 0.5]), ...
           struct('Colors', struct('Text', [1 NaN 1 1]))};
    for k = 1:numel(bad)
        f = fieldnames(bad{k});
        t_throws(['SetStyle refuses a bad ' f{1}], 'psychimgui:Range', ...
                 @() PsychImGui('SetStyle', bad{k}));
    end
    PsychImGui('SetGlobalScale', 0.2);
    section_begin();
    section_end();
    t_ok('a small global scale keeps the sizes Dear ImGui requires', true);
    PsychImGui('SetGlobalScale', 1);

    section_begin();
    a = PsychImGui('GetStyle').Alpha;
    PsychImGui('BeginDisabled', true);
    t_throws('GetStyle inside BeginDisabled', 'psychimgui:Usage', @() PsychImGui('GetStyle'));
    t_throws('SetStyle inside BeginDisabled', 'psychimgui:Usage', ...
             @() PsychImGui('SetStyle', struct('Alpha', 1)));
    PsychImGui('EndDisabled');
    t_eq('BeginDisabled did not reach the base', PsychImGui('GetStyle').Alpha, a);
    section_end();
end

function section_begin()
    PsychImGui('NewFrame', tf_input());
    PsychImGui('SetNextWindowPos', [0 0]);
    PsychImGui('SetNextWindowSize', [640 480]);
    PsychImGui('Begin', 'safety', [], 0);
end

function section_end()
    PsychImGui('End');
    PsychImGui('Render');
end
