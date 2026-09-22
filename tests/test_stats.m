function test_stats()
% TEST_STATS  The always-on counters count, and reset clears them.

    % Dear ImGui hides a window on the frame it first appears, while it
    % auto-fits, so a first frame produces no vertices. Warm up before
    % measuring.
    for warm = 1:2
        PsychImGui('NewFrame', tf_input());
        PsychImGui('Begin', 'stats');
        PsychImGui('Button', 'warm');
        PsychImGui('End');
        PsychImGui('Render');
    end

    PsychImGui('Stats', 'reset');
    s0 = PsychImGui('Stats');
    t_ok('Stats has perOp and frame', isstruct(s0) && isfield(s0, 'perOp') && ...
         isfield(s0, 'frame'));
    t_ok('perOp is empty after reset', isempty(s0.perOp) || ...
         ~any(strcmp({s0.perOp.name}, 'Button')));
    t_ok('reset clears the frame counters', s0.frame.vertices == 0);

    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'stats');
    for i = 1:25
        PsychImGui('Button', sprintf('b%d', i));
    end
    PsychImGui('End');
    PsychImGui('Render');

    s1 = PsychImGui('Stats');
    idx = find(strcmp({s1.perOp.name}, 'Button'), 1);
    t_ok('Button was counted', ~isempty(idx));
    t_eq('Button call count', s1.perOp(idx).calls, 25);
    t_ok('totalNs is positive', s1.perOp(idx).totalNs > 0);
    t_ok('maxNs does not exceed totalNs', ...
         s1.perOp(idx).maxNs <= s1.perOp(idx).totalNs);

    t_ok('frame newFrameNs recorded', s1.frame.newFrameNs > 0);
    t_ok('frame renderCpuNs recorded', s1.frame.renderCpuNs > 0);
    t_ok('renderGpuNs is zero without a GPU timer', s1.frame.renderGpuNs == 0);
    t_ok('vertices were produced', s1.frame.vertices > 0);
    t_ok('drawCalls were produced', s1.frame.drawCalls > 0);

    PsychImGui('Stats', 'reset');
    s2 = PsychImGui('Stats');
    t_ok('reset clears perOp', isempty(s2.perOp) || ...
         ~any(strcmp({s2.perOp.name}, 'Button')));
end
