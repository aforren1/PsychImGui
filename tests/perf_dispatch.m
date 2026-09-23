function r = perf_dispatch(n)
% PERF_DISPATCH  Per-call cost of the string path against the opcode path.
%
%   r = perf_dispatch()       200000 calls per case
%   r = perf_dispatch(n)      n calls per case
%
%   Measure, do not guess: the numbers below include the engine's own MEX call
%   overhead, which the binding cannot remove. The difference between the two
%   rows is what the name lookup costs.

    if nargin < 1
        n = 200000;
    end

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    addpath(fullfile(root, 'm'));
    PsychImGuiSetup();

    started = false;
    if isempty(getVersionSafe())
        error('perf_dispatch:noMEX', 'The PsychImGui MEX is not on the path.');
    end
    try
        PsychImGui('Init', 0, [0 0 640 480], zeros(256, 1, 'int32'), ...
                   struct('renderer', 'none', 'iniFile', ''));
        started = true;
    catch e
        if ~strcmp(e.identifier, 'psychimgui:AlreadyInit')
            rethrow(e);
        end
    end
    cleanup = onCleanup(@() localShutdown(started));

    op = PsychImGuiOp();
    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'perf');

    % Hoist the opcodes out of the loop. A struct field read costs more than
    % the dispatch it replaces on Octave, so leaving op.X inside the loop would
    % measure the engine, not the binding.
    opFrameCount = op.GetFrameCount;
    opButton = op.Button;

    % Warm up, so the first call does not pay for lazy loading.
    for i = 1:1000
        PsychImGui('GetFrameCount');
        PsychImGui(opFrameCount);
    end

    t = tic; for i = 1:n; PsychImGui('GetFrameCount'); end; tName0 = toc(t);
    t = tic; for i = 1:n; PsychImGui(opFrameCount); end; tOp0 = toc(t);
    t = tic; for i = 1:n; PsychImGui('Button', 'b'); end; tNameW = toc(t);
    t = tic; for i = 1:n; PsychImGui(opButton, 'b'); end; tOpW = toc(t);

    PsychImGui('End');
    PsychImGui('Render');

    % Draw list calls, the hot path of an overlay. One frame cannot hold n
    % lines: with 16 bit indices and no renderer to split them, Dear ImGui
    % asserts past 65536 vertices. So the calls run in frames of 5000, and
    % only the calls are timed.
    opAddLine = op.DrawList.AddLine;
    chunk = 5000;
    tNameL = 0;
    tOpL = 0;
    red = [1 0 0 1];
    for k = 1:ceil(n / chunk)
        m = min(chunk, n - (k - 1) * chunk);
        PsychImGui('NewFrame', tf_input());
        h = PsychImGui('GetForegroundDrawList');
        t = tic; for i = 1:m; PsychImGui('DrawList.AddLine', h, [0 0], [9 9], red); end
        tNameL = tNameL + toc(t);
        PsychImGui('Render');
        PsychImGui('NewFrame', tf_input());
        h = PsychImGui('GetForegroundDrawList');
        t = tic; for i = 1:m; PsychImGui(opAddLine, h, [0 0], [9 9], red); end
        tOpL = tOpL + toc(t);
        PsychImGui('Render');
    end

    r = struct('n', n, ...
               'nullaryNameUs', 1e6 * tName0 / n, ...
               'nullaryOpcodeUs', 1e6 * tOp0 / n, ...
               'buttonNameUs', 1e6 * tNameW / n, ...
               'buttonOpcodeUs', 1e6 * tOpW / n, ...
               'addLineNameUs', 1e6 * tNameL / n, ...
               'addLineOpcodeUs', 1e6 * tOpL / n);

    fprintf('perf_dispatch (%s, %d calls per case)\n', engineName(), n);
    fprintf('  GetFrameCount   name %7.3f us   opcode %7.3f us   delta %6.3f us\n', ...
            r.nullaryNameUs, r.nullaryOpcodeUs, r.nullaryNameUs - r.nullaryOpcodeUs);
    fprintf('  Button(label)   name %7.3f us   opcode %7.3f us   delta %6.3f us\n', ...
            r.buttonNameUs, r.buttonOpcodeUs, r.buttonNameUs - r.buttonOpcodeUs);
    fprintf('  DrawList.AddLine name %6.3f us   opcode %7.3f us   delta %6.3f us\n', ...
            r.addLineNameUs, r.addLineOpcodeUs, r.addLineNameUs - r.addLineOpcodeUs);

    s = PsychImGui('Stats');
    for name = {'Button', 'DrawList.AddLine'}
        idx = find(strcmp({s.perOp.name}, name{1}), 1);
        if ~isempty(idx)
            fprintf('  MEX side %s mean %.3f us, max %.3f us (Stats counters)\n', ...
                    name{1}, 1e-3 * s.perOp(idx).totalNs / s.perOp(idx).calls, ...
                    1e-3 * s.perOp(idx).maxNs);
        end
    end
end

function localShutdown(started)
    if started
        PsychImGui('Shutdown');
    end
end

function v = getVersionSafe()
    try
        v = PsychImGui('Version');
    catch
        v = [];
    end
end

function s = engineName()
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        s = ['Octave ' version()];
    else
        s = ['MATLAB ' version()];
    end
end
