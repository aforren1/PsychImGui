function t_eq(name, a, b)
% T_EQ  Record an equality assertion, treating NaN as equal to NaN.

    same = isequaln(a, b);
    t_ok(name, same);
    if ~same
        fprintf(2, '        (values differ)\n');
    end
end
