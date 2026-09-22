function t_isa(name, x, cls)
% T_ISA  Record a class assertion.

    t_ok(name, isa(x, cls));
    if ~isa(x, cls)
        fprintf(2, '        got class "%s"\n', class(x));
    end
end
