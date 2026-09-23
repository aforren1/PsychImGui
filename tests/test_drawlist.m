function test_drawlist()
% TEST_DRAWLIST  Draw list handles and the DrawList subcommands.
%
%   A draw list handle is a number, not a pointer. It is valid only between
%   NewFrame and Render of the frame that returned it, and a stale one must
%   raise psychimgui:InvalidHandle instead of reaching a dead pointer.

    %% handles in one frame
    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'dl');
    w = PsychImGui('GetWindowDrawList');
    b = PsychImGui('GetBackgroundDrawList');
    f = PsychImGui('GetForegroundDrawList');
    t_isa('a handle is a double', w, 'double');
    t_ok('the three draw lists differ', numel(unique([w b f])) == 3);
    t_eq('the same draw list gives the same handle', ...
         PsychImGui('GetWindowDrawList'), w);

    red = [1 0 0 1];
    PsychImGui('DrawList.AddLine', w, [10 10], [100 100], red);
    PsychImGui('DrawList.AddLine', w, [10 10], [100 100], red, 3);
    PsychImGui('DrawList.AddRect', w, [10 10], [60 40], red, 4, 2, ...
               'ImDrawFlags_RoundCornersTop');
    PsychImGui('DrawList.AddRectFilled', b, [0 0], [640 480], [0.1 0.1 0.1 1]);
    PsychImGui('DrawList.AddCircle', f, [320 240], 50, red, 32, 2);
    PsychImGui('DrawList.AddCircleFilled', f, [320 240], 20, [0 1 0 0.5]);
    PsychImGui('DrawList.AddTriangle', w, [0 0], [20 0], [10 20], red);
    PsychImGui('DrawList.AddTriangleFilled', w, [0 0], [20 0], [10 20], red);
    PsychImGui('DrawList.AddText', f, [5 5], [1 1 1 1], 'overlay');
    PsychImGui('DrawList.AddText', f, [5 20], [1 1 1 1], '');
    % A packed ABGR color is accepted as well as the 1x4 form.
    PsychImGui('DrawList.AddLine', w, [0 0], [5 5], 4278190335);
    t_ok('primitives draw', true);

    %% point lists
    pts = [0 0; 50 10; 100 0; 150 30];
    PsychImGui('DrawList.AddPolyline', w, pts, red, 2);
    PsychImGui('DrawList.AddPolyline', w, pts, red, 2, 'ImDrawFlags_Closed');
    PsychImGui('DrawList.AddConvexPolyFilled', f, [0 0; 40 0; 40 40; 0 40], red);
    PsychImGui('DrawList.AddPolyline', w, zeros(0, 2), red, 1);
    % Longer than the stack buffer, so the heap path runs too.
    t = linspace(0, 2 * pi, 1000)';
    PsychImGui('DrawList.AddPolyline', f, [320 + 100 * cos(t), 240 + 100 * sin(t)], red, 1);
    t_ok('point lists draw', true);
    t_throws('points must be Nx2', 'psychimgui:Type', ...
             @() PsychImGui('DrawList.AddPolyline', w, [0 0 0; 1 1 1], red, 1));
    t_throws('points must be double', 'psychimgui:Type', ...
             @() PsychImGui('DrawList.AddConvexPolyFilled', w, single(pts), red));

    %% colors
    t_throws('a 1x3 color is refused', 'psychimgui:Type', ...
             @() PsychImGui('DrawList.AddLine', w, [0 0], [1 1], [1 0 0]));
    t_throws('a negative packed color is refused', 'psychimgui:Range', ...
             @() PsychImGui('DrawList.AddLine', w, [0 0], [1 1], -1));

    %% clip rectangles
    PsychImGui('DrawList.PushClipRect', w, [0 0], [50 50]);
    PsychImGui('DrawList.PushClipRect', w, [10 10], [40 40], true);
    PsychImGui('DrawList.AddRectFilled', w, [0 0], [100 100], red);
    PsychImGui('DrawList.PopClipRect', w);
    PsychImGui('DrawList.PopClipRect', w);
    t_throws('a pop with no push is refused', 'psychimgui:Usage', ...
             @() PsychImGui('DrawList.PopClipRect', w));
    % The pushes are counted per draw list, not across them.
    PsychImGui('DrawList.PushClipRect', f, [0 0], [50 50]);
    t_throws('a push on one list does not pay for a pop on another', ...
             'psychimgui:Usage', @() PsychImGui('DrawList.PopClipRect', b));
    PsychImGui('DrawList.PopClipRect', f);

    %% handle validation
    t_throws('a handle must be numeric', 'psychimgui:Type', ...
             @() PsychImGui('DrawList.AddLine', 'w', [0 0], [1 1], red));
    t_throws('a handle must be a scalar', 'psychimgui:Type', ...
             @() PsychImGui('DrawList.AddLine', [w w], [0 0], [1 1], red));
    t_throws('a made up handle is refused', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', w + 1000, [0 0], [1 1], red));
    t_throws('a fractional handle is refused', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', w + 0.5, [0 0], [1 1], red));
    t_throws('0 is never a handle', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', 0, [0 0], [1 1], red));
    t_throws('a missing color is a usage error', 'psychimgui:Usage', ...
             @() PsychImGui('DrawList.AddLine', w, [0 0], [1 1]));

    PsychImGui('End');
    PsychImGui('Render');

    %% stale handles
    t_throws('a handle after Render is stale', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', w, [0 0], [1 1], red));
    t_throws('GetWindowDrawList outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('GetWindowDrawList'));
    t_throws('GetForegroundDrawList outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('GetForegroundDrawList'));

    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'dl');
    t_throws('a handle from the last frame is stale', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', w, [0 0], [1 1], red));
    t_throws('a background handle from the last frame is stale', ...
             'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddText', b, [0 0], red, 'x'));
    w2 = PsychImGui('GetWindowDrawList');
    t_ok('a new frame gives a new handle', w2 ~= w);
    PsychImGui('DrawList.AddLine', w2, [0 0], [1 1], red);
    % A clip push left open is legal; Dear ImGui resets the stack each frame.
    PsychImGui('DrawList.PushClipRect', w2, [0 0], [10 10]);
    PsychImGui('End');
    PsychImGui('EndFrame');
    t_throws('a handle after EndFrame is stale', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', w2, [0 0], [1 1], red));

    % A context torn down and made again must not revive an old handle, even
    % if Dear ImGui hands out the same pointers.
    PsychImGui('NewFrame', tf_input());
    w3 = PsychImGui('GetBackgroundDrawList');
    PsychImGui('Render');
    PsychImGui('Shutdown');
    PsychImGui('Init', 0, [0 0 640 480], zeros(256, 1, 'int32'), ...
               struct('renderer', 'none', 'iniFile', ''));
    PsychImGui('NewFrame', tf_input());
    t_throws('a handle from before Shutdown is stale', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', w3, [0 0], [1 1], red));
    PsychImGui('Render');

    %% opcode path
    op = PsychImGuiOp();
    t_ok('op.DrawList holds the methods', isfield(op, 'DrawList') && ...
         isfield(op.DrawList, 'AddLine'));
    PsychImGui('NewFrame', tf_input());
    h = PsychImGui(op.GetForegroundDrawList);
    PsychImGui(op.DrawList.AddCircleFilled, h, [10 10], 5, red);
    PsychImGui('Render');
    t_ok('the opcode path takes a handle', true);

    s = PsychImGui('Stats');
    names = {s.perOp.name};
    t_ok('Stats counts DrawList calls', any(strcmp(names, 'DrawList.AddLine')));
end
