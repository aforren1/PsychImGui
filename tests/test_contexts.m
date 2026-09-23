function test_contexts()
% TEST_CONTEXTS  Several contexts, one per window, with renderer 'none'.
%
%   Each context owns its Dear ImGui state, its input, and its Stats. The
%   test switches between two, interleaves their frames, checks that a draw
%   list handle does not cross from one to the other, and checks the handle
%   rules: a handle is never reused, and a handle of a context that was shut
%   down raises psychimgui:InvalidHandle.

    PsychImGui('Shutdown', 'all');   % run_tests opened a context for window 0
    km = zeros(256, 1, 'int32');
    opts = struct('renderer', 'none', 'iniFile', '');

    [c0, all0] = PsychImGui('GetContext');
    t_eq('no context is current after Shutdown all', c0, 0);
    t_ok('no context is live after Shutdown all', isempty(all0));

    %% two contexts
    a = PsychImGui('Init', 1, [0 0 640 480], km, opts);
    t_ok('Init returns a handle', isnumeric(a) && isscalar(a) && a > 0);
    t_eq('the new context is current', PsychImGui('GetContext'), a);
    b = PsychImGui('Init', 2, [0 0 320 240], km, opts);
    t_ok('a second window gets a second handle', b ~= a);
    t_eq('the second context is current', PsychImGui('GetContext'), b);
    [~, live] = PsychImGui('GetContext');
    t_eq('both contexts are live', sort(live), sort([a b]));
    t_eq('Version reports the current context', PsychImGui('Version').context, b);
    t_throws('Init twice for one window', 'psychimgui:AlreadyInit', ...
             @() PsychImGui('Init', 1, [0 0 640 480], km, opts));
    t_eq('a refused Init leaves the current context', PsychImGui('GetContext'), b);

    %% switching
    PsychImGui('SetContext', a);
    t_eq('SetContext switches', PsychImGui('GetContext'), a);
    t_throws('SetContext with a handle never issued', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('SetContext', 12345));
    t_throws('SetContext with a string', 'psychimgui:Type', ...
             @() PsychImGui('SetContext', 'a'));
    t_throws('SetContext with no handle', 'psychimgui:Usage', ...
             @() PsychImGui('SetContext'));
    t_eq('a refused SetContext leaves the current context', ...
         PsychImGui('GetContext'), a);

    %% frames stay apart
    % Three frames in a, one in b, interleaved: each context counts its own.
    for k = 1:3
        PsychImGui('SetContext', a);
        PsychImGui('NewFrame', tf_input());
        PsychImGui('Begin', 'in a');
        PsychImGui('SmallButton', 'only in a');
        PsychImGui('End');
        if k == 2
            PsychImGui('SetContext', b);
            PsychImGui('NewFrame', tf_input());
            PsychImGui('Begin', 'in b');
            PsychImGui('Button', 'only in b');
            PsychImGui('End');
            PsychImGui('Render');
            PsychImGui('SetContext', a);
        end
        PsychImGui('Render');
    end
    PsychImGui('SetContext', a);
    fa = PsychImGui('GetFrameCount');
    PsychImGui('SetContext', b);
    fb = PsychImGui('GetFrameCount');
    t_eq('context a counted its own frames', fa, 3);
    t_eq('context b counted its own frame', fb, 1);

    %% Stats are per context
    sa = local_stats(a);
    sb = local_stats(b);
    t_ok('a counted SmallButton', any(strcmp({sa.perOp.name}, 'SmallButton')));
    t_ok('b did not count SmallButton', isempty(sb.perOp) || ...
         ~any(strcmp({sb.perOp.name}, 'SmallButton')));
    t_ok('b counted Button', any(strcmp({sb.perOp.name}, 'Button')));
    PsychImGui('SetContext', a);
    PsychImGui('Stats', 'reset');
    sb2 = local_stats(b);
    t_ok('resetting a leaves b alone', any(strcmp({sb2.perOp.name}, 'Button')));

    %% a draw list handle does not cross contexts
    PsychImGui('SetContext', a);
    PsychImGui('NewFrame', tf_input());
    ha = PsychImGui('GetForegroundDrawList');
    PsychImGui('SetContext', b);
    PsychImGui('NewFrame', tf_input());
    t_throws('a handle of context a is stale in context b', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', ha, [0 0], [1 1], [1 1 1 1]));
    PsychImGui('Render');
    PsychImGui('SetContext', a);
    t_throws('and stays stale after switching back', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('DrawList.AddLine', ha, [0 0], [1 1], [1 1 1 1]));
    PsychImGui('Render');

    %% Shutdown by handle
    PsychImGui('SetContext', b);
    PsychImGui('Shutdown', a);
    t_eq('shutting down a keeps b current', PsychImGui('GetContext'), b);
    t_throws('a is stale after its Shutdown', 'psychimgui:InvalidHandle', ...
             @() PsychImGui('SetContext', a));
    PsychImGui('Shutdown', a);
    t_ok('Shutdown of a stale handle is a no-op', true);
    t_throws('Shutdown with a word other than all', 'psychimgui:Usage', ...
             @() PsychImGui('Shutdown', 'some'));
    t_throws('Shutdown with two arguments', 'psychimgui:Usage', ...
             @() PsychImGui('Shutdown', b, 1));

    %% Shutdown with no argument shuts down the current context only
    c = PsychImGui('Init', 3, [0 0 640 480], km, opts);
    PsychImGui('SetContext', b);
    PsychImGui('Shutdown');
    t_eq('nothing is current after Shutdown', PsychImGui('GetContext'), 0);
    t_throws('a widget with nothing current', 'psychimgui:NotInit', ...
             @() PsychImGui('Button', 'x'));
    [~, live] = PsychImGui('GetContext');
    t_eq('the other context lives on', live, c);
    t_ok('handles are never reused', c > b && c > a);

    %% the MEX stays locked while any context lives
    lockedLive = local_locked();
    PsychImGui('Shutdown', 'all');
    lockedNone = local_locked();
    if ~isempty(lockedLive)
        t_ok('the MEX is locked while a context lives', lockedLive);
        t_ok('the MEX is unlocked with no context left', ~lockedNone);
    end

    %% the table holds eight contexts
    hs = zeros(1, 8);
    for k = 1:8
        hs(k) = PsychImGui('Init', 100 + k, [0 0 64 64], km, opts);
    end
    t_eq('eight contexts are live', numel(unique(hs)), 8);
    t_throws('a ninth context is refused', 'psychimgui:Context', ...
             @() PsychImGui('Init', 200, [0 0 64 64], km, opts));
    PsychImGui('Shutdown', 'all');
    [cur, live] = PsychImGui('GetContext');
    t_ok('Shutdown all leaves nothing', cur == 0 && isempty(live));
end

function s = local_stats(h)
    PsychImGui('SetContext', h);
    s = PsychImGui('Stats');
end

function tf = local_locked()
    % mislocked answers for a MEX on both engines; an engine without it
    % skips the check rather than failing it.
    try
        tf = mislocked('PsychImGui');
    catch
        tf = [];
    end
end
