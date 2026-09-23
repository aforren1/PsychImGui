function run_tests()
% RUN_TESTS  The psychimgui test suite, with no GPU and no Psychtoolbox.
%
%   Run from anywhere:  run_tests
%
%   Every test runs with opts.renderer = 'none', so Dear ImGui builds its font
%   atlas in software and Render discards the draw data. The suite passes under
%   both MATLAB and Octave. The Psychtoolbox tests in tests/gl need a real
%   window and are not run from here.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    TST_PASS = 0;
    TST_FAIL = 0;

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    addpath(here);
    addpath(fullfile(root, 'm'));
    PsychImGuiSetup();   % dist/<arch> ahead of m/, or a clear error

    % The recording Screen stub that test_helpers needs goes on the path now,
    % before the first call loads the MEX, and comes off once at the very end.
    % Octave 10.1 on Linux recurses without end in out_of_date_check when the
    % load path changes while a locked MEX is loaded, so every path change in
    % this run happens while no MEX is loaded. See SPEC.md section 14.6.
    tf_screen('install');

    % exist(...,'file') answers 2 when m/PsychImGui.m is also on the path, so
    % test the MEX by calling it instead of by its file type.
    try
        v = PsychImGui('Version');
    catch
        error('run_tests:noMEX', ...
              'The PsychImGui MEX is not built or not callable; run build first.');
    end
    fprintf('psychimgui %s, Dear ImGui %s (%d), ImPlot %d, build %s\n', ...
            v.psychimgui, v.imgui, v.imguiNum, v.implot, v.build);

    % A stale context from an interrupted run would make Init fail.
    PsychImGui('Shutdown');

    tests = {@test_dispatch, @test_gen_marshal, @test_inputtext, ...
             @test_tables, @test_drawlist, @test_image, ...
             @test_keymap, @test_stats, @test_assert, @test_helpers};
    for i = 1:numel(tests)
        name = func2str(tests{i});
        fprintf('\n---- %s ----\n', name);
        p0 = TST_PASS; f0 = TST_FAIL;
        try
            local_fresh_context(name);
            tests{i}();
        catch e
            TST_FAIL = TST_FAIL + 1;
            fprintf(2, '  FAIL  %s threw %s: %s\n', name, e.identifier, e.message);
        end
        PsychImGui('Shutdown');
        fprintf('  %d passed, %d failed\n', TST_PASS - p0, TST_FAIL - f0);
    end

    % The Screen stub comes off the path here, after the last test and the
    % last Shutdown. Between install and cleanup nothing changes the path.
    try
        tf_screen('cleanup');
    catch
    end

    fprintf('\n==== %d passed, %d failed ====\n', TST_PASS, TST_FAIL);
    if TST_FAIL > 0
        error('run_tests:failed', '%d test(s) failed', TST_FAIL);
    end
end

function local_fresh_context(name)
    % test_dispatch owns its own lifecycle, because it checks Init and
    % Shutdown themselves.
    if strcmp(name, 'test_dispatch')
        return;
    end
    PsychImGui('Shutdown');
    PsychImGui('Init', 0, [0 0 640 480], PsychImGuiKeymapOrEmpty(), ...
               struct('renderer', 'none', 'iniFile', ''));
end

function m = PsychImGuiKeymapOrEmpty()
    try
        m = PsychImGuiKeymap();
    catch
        m = zeros(256, 1, 'int32');
    end
end
