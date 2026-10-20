function test_style()
% TEST_STYLE  GetStyle, SetStyle, and SetGlobalScale (SPEC.md 14.16).
%
%   The style comes back without the global scale, so a theme saved at one
%   scale loads the same at another. The live, scaled style is checked
%   through GetFrameHeight, which is the font size plus twice FramePadding.y.

    %% the struct
    s = PsychImGui('GetStyle');
    t_ok('GetStyle is one struct', isstruct(s) && isscalar(s));
    t_ok('a float field', isnumeric(s.WindowRounding) && isscalar(s.WindowRounding));
    t_eq('an ImVec2 field is 1x2', size(s.WindowPadding), [1 2]);
    t_isa('a bool field is logical', s.AntiAliasedLines, 'logical');
    t_ok('Colors is a struct of 1x4 colors', isstruct(s.Colors) && ...
         isequal(size(s.Colors.WindowBg), [1 4]));
    t_ok('the scale is not a theme field', ~isfield(s, 'FontScaleMain'));
    PsychImGui('SetStyle', s);
    t_ok('a round trip changes nothing', isequal(PsychImGui('GetStyle'), s));

    %% partial structs, and a failed call changes nothing
    PsychImGui('SetStyle', struct('WindowRounding', 7));
    t_eq('a partial struct sets one field', PsychImGui('GetStyle').WindowRounding, 7);
    PsychImGui('SetStyle', struct('Colors', struct('WindowBg', [0.1 0.2 0.3 0.9])));
    c = PsychImGui('GetStyle').Colors.WindowBg;
    t_ok('a partial Colors struct sets one color', max(abs(c - [0.1 0.2 0.3 0.9])) < 1e-6);
    t_throws('an unknown field', 'psychimgui:Usage', ...
             @() PsychImGui('SetStyle', struct('WindowRoundness', 1)));
    t_throws('an unknown color', 'psychimgui:Usage', ...
             @() PsychImGui('SetStyle', struct('Colors', struct('Windowbg', [0 0 0 1]))));
    t_throws('a NaN size', 'psychimgui:Range', ...
             @() PsychImGui('SetStyle', struct('FrameRounding', NaN)));
    t_throws('an ImGuiDir out of range', 'psychimgui:Range', ...
             @() PsychImGui('SetStyle', struct('WindowMenuButtonPosition', 7)));
    t_throws('a color that is not 1x4', 'psychimgui:Type', ...
             @() PsychImGui('SetStyle', struct('Colors', struct('Text', [1 1 1]))));
    t_throws('a struct array', 'psychimgui:Type', ...
             @() PsychImGui('SetStyle', [s s]));
    try
        PsychImGui('SetStyle', struct('WindowRounding', 2, 'Bogus', 1));
    catch
    end
    t_eq('a failed SetStyle changes no field', PsychImGui('GetStyle').WindowRounding, 7);
    PsychImGui('SetStyle', struct('WindowMenuButtonPosition', 'ImGuiDir_Right', ...
                                  'TreeLinesFlags', 'ImGuiTreeNodeFlags_DrawLinesFull'));
    t_eq('enums and flags by name', PsychImGui('GetStyle').WindowMenuButtonPosition, ...
         PsychImGui('Enum', 'ImGuiDir_Right'));

    %% the global scale
    PsychImGui('SetStyle', struct('FramePadding', [4 3], 'WindowRounding', 3));
    h1 = frame_height();
    PsychImGui('SetGlobalScale', 2);
    h2 = frame_height();
    t_eq('scale 2 doubles the frame height', h2, 2 * h1);
    PsychImGui('SetGlobalScale', 2);
    t_eq('a second SetGlobalScale does not compound', frame_height(), h2);
    st = PsychImGui('GetStyle');
    t_ok('GetStyle is unscaled', isequal(st.FramePadding, [4 3]) && st.WindowRounding == 3);
    PsychImGui('SetGlobalScale', 1.25);
    t_eq('a truncated size reads back exactly', PsychImGui('GetStyle').WindowRounding, 3);
    PsychImGui('SetStyle', struct('FramePadding', [8 6]));
    PsychImGui('SetGlobalScale', 1);
    t_eq('SetStyle under a scale stores the unscaled value', frame_height(), h1 + 6);
    PsychImGui('SetStyle', struct('FramePadding', [4 3]));

    %% presets reach the base
    PsychImGui('StyleColorsLight');
    light = PsychImGui('GetStyle').Colors.WindowBg;
    PsychImGui('StyleColorsDark');
    dark = PsychImGui('GetStyle').Colors.WindowBg;
    t_ok('a preset shows in GetStyle', mean(light(1:3)) > mean(dark(1:3)));

    %% a theme file (jsonencode arrived in Octave 7)
    PsychImGui('SetStyle', struct('WindowRounding', 5, 'Alpha', 0.9));
    s = PsychImGui('GetStyle');
    if exist('jsonencode') ~= 0 %#ok<EXIST>
        f = [tempname '.json'];
        fid = fopen(f, 'w');
        fprintf(fid, '%s', jsonencode(s));
        fclose(fid);
        PsychImGui('StyleColorsLight');
        PsychImGui('SetStyle', struct('WindowRounding', 0, 'Alpha', 1));
        PsychImGui('SetStyle', jsondecode(fileread(f)));
        delete(f);
        t_ok('a JSON theme round trips exactly', isequal(PsychImGui('GetStyle'), s));
    end

    %% pushes block the calls that would freeze or lose them
    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'style');
    t_ok('GetStyle works in a frame', isstruct(PsychImGui('GetStyle')));
    PsychImGui('PushStyleVar', 'ImGuiStyleVar_Alpha', 0.5);
    t_throws('GetStyle under a PushStyleVar', 'psychimgui:Usage', @() PsychImGui('GetStyle'));
    t_throws('SetGlobalScale under a PushStyleVar', 'psychimgui:Usage', ...
             @() PsychImGui('SetGlobalScale', 2));
    PsychImGui('PopStyleVar');
    PsychImGui('PushStyleColor', 'ImGuiCol_Text', [1 0 0 1]);
    t_throws('SetStyle under a PushStyleColor', 'psychimgui:Usage', ...
             @() PsychImGui('SetStyle', struct('Alpha', 1)));
    PsychImGui('PopStyleColor');
    t_ok('the pushed value did not reach the base', ...
         abs(PsychImGui('GetStyle').Alpha - 0.9) < 1e-6);

    %% ImPlot and ImPlot3D
    p = PsychImGui('ImPlot.GetStyle');
    t_ok('ImPlot.GetStyle has Colors and Colormap', isfield(p, 'Colors') && isfield(p, 'Colormap'));
    PsychImGui('ImPlot.SetStyle', struct('PlotPadding', [3 4], 'Colormap', 2));
    p = PsychImGui('ImPlot.GetStyle');
    t_ok('ImPlot.SetStyle sets fields', isequal(p.PlotPadding, [3 4]) && p.Colormap == 2);
    t_throws('an ImPlot colormap past the count', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot.SetStyle', ...
                            struct('Colormap', PsychImGui('ImPlot.GetColormapCount'))));
    PsychImGui('ImPlot.SetStyle', p);
    t_ok('an ImPlot round trip changes nothing', isequal(PsychImGui('ImPlot.GetStyle'), p));
    PsychImGui('ImPlot.PushStyleVarVec2', 'ImPlotStyleVar_PlotPadding', [0 0]);
    t_throws('ImPlot.GetStyle under a push', 'psychimgui:Usage', ...
             @() PsychImGui('ImPlot.GetStyle'));
    PsychImGui('ImPlot.PopStyleVar');
    q = PsychImGui('ImPlot3D.GetStyle');
    PsychImGui('ImPlot3D.SetStyle', struct('LineWeight', 2, 'Marker', 'ImPlot3DMarker_Square'));
    q2 = PsychImGui('ImPlot3D.GetStyle');
    t_ok('ImPlot3D.SetStyle sets fields', q2.LineWeight == 2 && ...
         q2.Marker == PsychImGui('Enum', 'ImPlot3DMarker_Square'));
    t_throws('an ImPlot3D marker out of range', 'psychimgui:Range', ...
             @() PsychImGui('ImPlot3D.SetStyle', struct('Marker', 10)));
    PsychImGui('ImPlot3D.SetStyle', q);
    t_ok('an ImPlot3D round trip changes nothing', isequal(PsychImGui('ImPlot3D.GetStyle'), q));
    PsychImGui('End');
    PsychImGui('Render');
end

function h = frame_height()
    % The live style takes effect at NewFrame, which also applies the font
    % scale, so measure in a frame of its own.
    PsychImGui('NewFrame', tf_input());
    h = PsychImGui('GetFrameHeight');
    PsychImGui('Render');
end
