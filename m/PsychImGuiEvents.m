function out = PsychImGuiEvents(cmd, E, varargin)
% PsychImGuiEvents  Read the device events of PsychImGuiInput('Poll').
%
%   S = PsychImGuiEvents('decode', E)
%       Struct array, one element per row of E = in.events, with the
%       fields time, device, kind ('key', 'button', or 'wheel'), code,
%       name, pressed, and cooked. name is the KbName of a key ('' when
%       KbName is not available), 'left', 'middle', 'right', 'back', or
%       'forward' for a button, and 'vertical' or 'horizontal' for the
%       wheel.
%
%   R = PsychImGuiEvents('filter', E, kind, code)
%       The rows of E of that kind and code. kind is 1, 2, 3 or 'key',
%       'button', 'wheel'. code is a number, or for keys a KbName name such
%       as 'space'. Pass [] for either to leave it unconstrained.
%
%   The matrix is the primary form because it costs one allocation per
%   frame. Decode it when readability matters more than time.
%
%   A reaction time, from the Flip that showed the stimulus to the first
%   press of the space bar:
%
%       tOn = Screen('Flip', win);
%       rt = [];
%       while isempty(rt)
%           ig = PsychImGuiFrame('Begin', ig);
%           PsychImGuiFrame('End', ig);
%           Screen('Flip', win);
%           R = PsychImGuiEvents('filter', ig.in.events, 'key', 'space');
%           R = R(R(:, 5) == 1 & R(:, 1) >= tOn, :);
%           if ~isempty(R)
%               rt = R(1, 1) - tOn;
%           end
%       end
%
%   See also PsychImGuiInput, PsychImGuiFrame, KbName.

    switch lower(cmd)
        case 'decode'
            out = local_decode(E);
        case 'filter'
            out = local_filter(E, varargin{:});
        otherwise
            error('psychimgui:Usage', 'PsychImGuiEvents: unknown subcommand "%s".', cmd);
    end
end

function S = local_decode(E)
    local_check(E);
    kinds = {'key', 'button', 'wheel'};
    n = size(E, 1);
    S = repmat(struct('time', 0, 'device', 0, 'kind', '', 'code', 0, 'name', '', ...
                      'pressed', 0, 'cooked', 0), n, 1);
    for k = 1:n
        S(k).time = E(k, 1);
        S(k).device = E(k, 2);
        S(k).code = E(k, 4);
        S(k).pressed = E(k, 5);
        S(k).cooked = E(k, 6);
        if E(k, 3) >= 1 && E(k, 3) <= 3
            S(k).kind = kinds{E(k, 3)};
        end
        S(k).name = local_name(E(k, 3), E(k, 4));
    end
end

function name = local_name(kind, code)
    name = '';
    switch kind
        case 1
            try
                name = KbName(code);
            catch
                % Without Psychtoolbox the keycode is all there is.
            end
            if ~ischar(name)
                name = '';
            end
        case 2
            names = {1, 'left'; 2, 'middle'; 3, 'right'; 8, 'back'; 9, 'forward'};
            k = find([names{:, 1}] == code, 1);
            if ~isempty(k)
                name = names{k, 2};
            end
        case 3
            if code == 1
                name = 'vertical';
            elseif code == 2
                name = 'horizontal';
            end
    end
end

function R = local_filter(E, kind, code)
    local_check(E);
    if nargin < 2
        kind = [];
    end
    if nargin < 3
        code = [];
    end
    if ischar(kind)
        k = find(strcmpi(kind, {'key', 'button', 'wheel'}), 1);
        if isempty(k)
            error('psychimgui:Usage', ...
                  'PsychImGuiEvents: kind must be key, button, or wheel, not "%s".', kind);
        end
        kind = k;
    end
    if ischar(code)
        if kind ~= 1
            error('psychimgui:Usage', 'PsychImGuiEvents: a code name needs kind ''key''.');
        end
        code = KbName(code);
    end
    keep = true(size(E, 1), 1);
    if ~isempty(kind)
        keep = keep & E(:, 3) == kind;
    end
    if ~isempty(code)
        keep = keep & ismember(E(:, 4), code);
    end
    R = E(keep, :);
end

function local_check(E)
    if ~isnumeric(E) || (~isempty(E) && size(E, 2) ~= 6)
        error('psychimgui:Type', 'PsychImGuiEvents: E must be the Nx6 in.events matrix.');
    end
end
