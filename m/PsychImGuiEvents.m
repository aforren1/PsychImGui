function out = PsychImGuiEvents(cmd, E, varargin)
% PsychImGuiEvents  Select device events of PsychImGuiInput('Poll').
%
%   R = PsychImGuiEvents('filter', E, kind, code)
%       The elements of E = in.events of that kind and code, in their
%       order, as an Mx1 struct array. kind is 'key', 'button', or 'wheel'.
%       code is a number, or for keys a KbName name such as 'space'. Pass []
%       for either to leave it unconstrained. An empty E gives an empty R.
%
%   in.events is an Nx1 struct array with the fields time, device, kind,
%   code, name, pressed, and cooked; PsychImGuiInput describes them. The
%   fields can also be read directly, without this function:
%
%       t = [E([E.code] == KbName('space') & [E.pressed] == 1).time];
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
%           t = [R([R.pressed] == 1 & [R.time] >= tOn).time];
%           if ~isempty(t)
%               rt = t(1) - tOn;
%           end
%       end
%
%   See also PsychImGuiInput, PsychImGuiFrame, KbName.

    switch lower(cmd)
        case 'filter'
            out = local_filter(E, varargin{:});
        otherwise
            error('psychimgui:Usage', ...
                  ['PsychImGuiEvents: unknown subcommand "%s". in.events is a ' ...
                   'struct array, so there is nothing to decode.'], cmd);
    end
end

function R = local_filter(E, kind, code)
    if nargin < 2
        kind = [];
    end
    if nargin < 3
        code = [];
    end
    if isempty(E)
        R = E;
        return;
    end
    if ~isstruct(E) || ~isfield(E, 'kind') || ~isfield(E, 'code')
        error('psychimgui:Type', 'PsychImGuiEvents: E must be the in.events struct array.');
    end
    if ~isempty(kind) && ~any(strcmp(kind, {'key', 'button', 'wheel'}))
        error('psychimgui:Usage', ...
              'PsychImGuiEvents: kind must be key, button, or wheel.');
    end
    if ischar(code)
        if ~strcmp(kind, 'key')
            error('psychimgui:Usage', 'PsychImGuiEvents: a code name needs kind ''key''.');
        end
        code = KbName(code);
    end
    keep = true(numel(E), 1);
    if ~isempty(kind)
        keep = keep & strcmp({E.kind}, kind)';
    end
    if ~isempty(code)
        keep = keep & ismember([E.code], code)';
    end
    R = E(keep);
    R = R(:);
end
