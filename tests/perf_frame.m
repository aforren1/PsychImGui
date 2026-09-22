function perf_frame(nWidgets, nFrames)
% PERF_FRAME  Frame cost with many widgets.
%
%   perf_frame()            200 sliders for 600 frames
%   perf_frame(n, f)        n sliders for f frames
%
%   Prints the Stats counters and a coarse frame time histogram. Runs with
%   renderer='none', so the numbers are the CPU cost of the binding and of
%   Dear ImGui, without the GPU.

    if nargin < 1; nWidgets = 200; end
    if nargin < 2; nFrames = 600; end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    addpath(fullfile(root, 'm'));
    PsychImGuiSetup();

    PsychImGui('Shutdown');
    PsychImGui('Init', 0, [0 0 1280 960], zeros(256, 1, 'int32'), ...
               struct('renderer', 'none', 'iniFile', ''));
    cleanup = onCleanup(@() PsychImGui('Shutdown'));

    op = PsychImGuiOp();
    labels = cell(1, nWidgets);
    for i = 1:nWidgets
        labels{i} = sprintf('v%d', i);
    end
    vals = rand(1, nWidgets);
    trace = sin(linspace(0, 20, 1024));

    PsychImGui('Stats', 'reset');
    ft = zeros(1, nFrames);
    for f = 1:nFrames
        t0 = tic;
        PsychImGui('NewFrame', tf_input(f / 60));
        PsychImGui('Begin', 'perf');
        for i = 1:nWidgets
            [~, vals(i)] = PsychImGui(op.SliderFloat, labels{i}, vals(i), 0, 1);
        end
        PsychImGui('PlotLines', 'trace', trace);
        PsychImGui('End');
        PsychImGui('Render');
        ft(f) = toc(t0) * 1e3;
    end

    s = PsychImGui('Stats');
    fprintf('perf_frame: %d widgets, %d frames\n', nWidgets, nFrames);
    fprintf('  frame time  mean %.3f ms  median %.3f ms  p95 %.3f ms  max %.3f ms\n', ...
            mean(ft), median(ft), prctileLocal(ft, 95), max(ft));
    fprintf('  NewFrame %.3f ms, Render CPU %.3f ms, %d draw calls, %d vertices\n', ...
            s.frame.newFrameNs / 1e6, s.frame.renderCpuNs / 1e6, ...
            s.frame.drawCalls, s.frame.vertices);

    edges = [0 0.5 1 2 4 8 16 32 Inf];
    fprintf('  histogram (ms):\n');
    for i = 1:numel(edges) - 1
        c = sum(ft >= edges(i) & ft < edges(i + 1));
        fprintf('    %6.1f to %6.1f  %5d  %s\n', edges(i), edges(i + 1), c, ...
                repmat('#', 1, round(60 * c / nFrames)));
    end
end

function p = prctileLocal(x, q)
    % Avoid the Statistics Toolbox, which Octave does not ship either.
    y = sort(x);
    p = y(max(1, min(numel(y), round(q / 100 * numel(y)))));
end
