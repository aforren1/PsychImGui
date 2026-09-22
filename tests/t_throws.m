function t_throws(name, id, fn)
% T_THROWS  Record that fn raises the expected error identifier.

    try
        fn();
    catch e
        t_ok(name, strcmp(e.identifier, id));
        if ~strcmp(e.identifier, id)
            fprintf(2, '        got id "%s" (%s)\n', e.identifier, e.message);
        end
        return;
    end
    t_ok(name, false);
    fprintf(2, '        %s did not throw\n', name);
end
