function test_inputtext()
% TEST_INPUTTEXT  Text round trip, non-ASCII, and bufSize truncation.
%
%   Section 7.5: the script owns the text. The MEX copies it into a buffer,
%   calls ImGui::InputText, and hands the buffer back. Without user input the
%   text must come back unchanged.

    PsychImGui('NewFrame', tf_input());
    PsychImGui('Begin', 'text');

    [changed, s] = PsychImGui('InputText', 'ascii', 'hello world');
    t_ok('ascii unchanged flag', islogical(changed) && ~changed);
    t_eq('ascii round trip', s, 'hello world');
    t_isa('output is char', s, 'char');

    [~, e] = PsychImGui('InputText', 'empty', '');
    t_ok('empty round trip', ischar(e) && isempty(e));

    % Non-ASCII text. MATLAB char holds UTF-16 code units, Octave char holds
    % UTF-8 bytes, so the same three code points are written differently per
    % engine. Building them from numbers keeps the test independent of how the
    % engine decodes this source file.
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        u = char([195 169 206 188 228 189 160]);   % UTF-8 of U+00E9 U+03BC U+4F60
        astral = char([240 159 152 128]);          % UTF-8 of U+1F600
    else
        u = char([233 956 20320]);                 % U+00E9 U+03BC U+4F60
        astral = char([55357 56832]);              % U+1F600 as a surrogate pair
    end
    [~, ru] = PsychImGui('InputText', 'unicode', u);
    t_eq('non-ASCII round trip', ru, u);
    t_eq('non-ASCII length', numel(ru), numel(u));

    [~, ra] = PsychImGui('InputText', 'astral', astral);
    t_eq('astral round trip', ra, astral);

    % bufSize truncates. The buffer floor is 256 bytes, so ask for more than
    % that to see the cut.
    long = repmat('a', 1, 600);
    [~, rt] = PsychImGui('InputText', 'trunc', long, 300);
    t_ok('bufSize truncates', numel(rt) == 299);
    t_eq('truncated content', rt, repmat('a', 1, 299));

    % A buffer larger than the inline one exercises the heap fallback.
    big = repmat('b', 1, 4000);
    [~, rb] = PsychImGui('InputText', 'heap', big, 8192);
    t_eq('heap buffer round trip', rb, big);

    [~, rm] = PsychImGui('InputTextMultiline', 'multi', sprintf('a\nb\nc'));
    t_eq('multiline round trip', rm, sprintf('a\nb\nc'));

    [~, rh] = PsychImGui('InputTextWithHint', 'hinted', 'hint here', 'value');
    t_eq('with hint round trip', rh, 'value');

    t_throws('numeric text rejected', 'psychimgui:Type', ...
             @() PsychImGui('InputText', 'bad', 42));

    PsychImGui('End');
    PsychImGui('Render');
end
