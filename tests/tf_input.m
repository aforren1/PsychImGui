function in = tf_input(t)
% TF_INPUT  A synthetic PsychImGui input struct for the headless tests.
%
%   The renderer='none' tests never touch a device, so they feed NewFrame a
%   fixed struct instead of PsychImGuiInput('Poll').

    persistent tick
    if isempty(tick)
        tick = 0;
    end
    tick = tick + 1;
    if nargin < 1
        t = tick / 60;
    end
    in = struct('mouse', [10 10 1], 'buttons', [0 0 0 0 0], 'wheel', [0 0], ...
                'keys', zeros(0, 4), 'display', [640 480], 'time', t, ...
                'focus', 1, 'fbscale', 1);
end
