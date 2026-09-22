function t_ok(name, cond)
% T_OK  Record one assertion in the global pass and fail counters.
%
%   Subfunctions cannot share a workspace across files under Octave, so the
%   harness uses globals, as in the user's mex-msgpack project.

    global TST_PASS TST_FAIL %#ok<GVMIS>
    if cond
        TST_PASS = TST_PASS + 1;
    else
        TST_FAIL = TST_FAIL + 1;
        fprintf(2, '  FAIL  %s\n', name);
    end
end
