function test_filedialog()
% TEST_FILEDIALOG  FileDialog.* argument rules and the dialog cycle, headless.
%
%   Nobody clicks in a headless run, so this checks what can be checked
%   without a user: the argument rules, the open, display, and close cycle,
%   the empty answers before a choice, and that a path outside ASCII reaches
%   the dialog and comes back unchanged on both engines.

    v = PsychImGui('Version');
    if ~v.fileDialog
        fprintf('  ImGuiFileDialog is not compiled in, skipping.\n');
        return;
    end
    t_ok('Version names the dialog version', ischar(v.fileDialogVersion) && ...
         ~isempty(v.fileDialogVersion));

    %% arguments
    t_throws('Open needs three arguments', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.Open', 'k', 'title'));
    t_throws('Open takes at most seven', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.Open', 'k', 't', '.m', '.', '', 1, 0, 9));
    t_throws('Open key must be char', 'psychimgui:Type', ...
             @() PsychImGui('FileDialog.Open', 7, 'title', '.m'));
    t_throws('Open key must not be empty', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.Open', '', 'title', '.m'));
    t_throws('Open maxSelection must not be negative', 'psychimgui:Range', ...
             @() PsychImGui('FileDialog.Open', 'k', 'title', '.m', '.', '', -1));
    t_throws('Open flags must be known names', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.Open', 'k', 'title', '.m', '.', '', 1, ...
                            'ImGuiFileDialogFlags_Nope'));
    t_eq('the dialog flags are in the enum table', ...
         PsychImGui('Enum', 'ImGuiFileDialogFlags_Modal'), 512);
    t_throws('Display needs a key', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.Display'));
    t_throws('Display outside a frame', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.Display', 'k'));
    t_throws('IsOk takes no arguments', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.IsOk', 1));
    t_throws('GetSelection takes no arguments', 'psychimgui:Usage', ...
             @() PsychImGui('FileDialog.GetSelection', 1));

    %% before any Open
    t_eq('IsOpened before Open', PsychImGui('FileDialog.IsOpened'), false);
    t_eq('IsOk before Open', PsychImGui('FileDialog.IsOk'), false);
    t_eq('GetFilePathName before Open', PsychImGui('FileDialog.GetFilePathName'), '');
    sel = PsychImGui('FileDialog.GetSelection');
    t_ok('GetSelection before Open is an empty cell', iscell(sel) && isempty(sel));
    PsychImGui('FileDialog.Close');
    t_ok('Close before Open is safe', true);

    %% a path outside ASCII, created for the test
    dirName = ['psychimgui_', local_utf(252), local_utf(8364)];   % u-umlaut, euro
    base = fullfile(tempdir(), dirName);
    if ~exist(base, 'dir')
        mkdir(base);
    end
    cleaner = onCleanup(@() local_rmdir(base));
    fid = fopen(fullfile(base, 'trial.csv'), 'w');
    if fid >= 0
        fclose(fid);
    end

    %% the cycle
    PsychImGui('FileDialog.Open', 'pick', 'Choose a file', '.csv,.txt', base, '', 2, ...
               {'ImGuiFileDialogFlags_DontShowHiddenFiles'});
    t_eq('IsOpened after Open', PsychImGui('FileDialog.IsOpened', 'pick'), true);
    t_eq('IsOpened with another key', PsychImGui('FileDialog.IsOpened', 'other'), false);
    for f = 1:3
        PsychImGui('NewFrame', tf_input());
        [done, open] = PsychImGui('FileDialog.Display', 'pick', [400 300]);
        [doneOther, openOther] = PsychImGui('FileDialog.Display', 'other');
        PsychImGui('Render');
    end
    t_eq('Display is not done without a choice', done, false);
    t_eq('Display reports the dialog open', open, true);
    t_eq('Display of another key is not done', doneOther, false);
    t_eq('Display of another key is not open', openOther, false);

    here = PsychImGui('FileDialog.GetCurrentPath');
    fprintf('  current path: %d chars, expected %d\n', numel(here), numel(base));
    t_ok('a path outside ASCII comes back unchanged', ...
         strcmp(local_norm(here), local_norm(base)));
    t_eq('IsOk without a choice', PsychImGui('FileDialog.IsOk'), false);

    PsychImGui('FileDialog.Close');
    t_eq('IsOpened after Close', PsychImGui('FileDialog.IsOpened', 'pick'), false);
    PsychImGui('NewFrame', tf_input());
    [done, open] = PsychImGui('FileDialog.Display', 'pick');
    PsychImGui('Render');
    t_ok('a closed dialog displays nothing', ~done && ~open);

    % An empty filter makes a directory chooser.
    PsychImGui('FileDialog.Open', 'dir', 'Choose a folder', '', base);
    PsychImGui('NewFrame', tf_input());
    [~, open] = PsychImGui('FileDialog.Display', 'dir');
    PsychImGui('Render');
    t_ok('a directory chooser opens', open);
    PsychImGui('FileDialog.Close');

    % Each context owns its dialog.
    km = zeros(256, 1, 'int32');
    PsychImGui('FileDialog.Open', 'mine', 'In context one', '.csv', base);
    first = PsychImGui('GetContext');
    second = PsychImGui('Init', 77, [0 0 640 480], km, ...
                        struct('renderer', 'none', 'iniFile', ''));
    t_eq('a new context has no open dialog', PsychImGui('FileDialog.IsOpened'), false);
    PsychImGui('SetContext', first);
    t_eq('the first context keeps its dialog', PsychImGui('FileDialog.IsOpened', 'mine'), ...
         true);
    PsychImGui('FileDialog.Close');
    PsychImGui('Shutdown', second);
end

function c = local_utf(cp)
    % One code point as the engine stores char: UTF-16 on MATLAB, UTF-8
    % bytes on Octave. The same approach as test_inputtext.
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        if cp < 128
            c = char(cp);
        elseif cp < 2048
            c = char([192 + floor(cp / 64), 128 + mod(cp, 64)]);
        else
            c = char([224 + floor(cp / 4096), 128 + mod(floor(cp / 64), 64), ...
                      128 + mod(cp, 64)]);
        end
    else
        c = char(cp);
    end
end

function p = local_norm(p)
    p = strrep(p, '\', '/');
    while numel(p) > 1 && p(end) == '/'
        p = p(1:end - 1);
    end
    if ispc
        p = lower(p);
    end
end

function local_rmdir(d)
    try
        delete(fullfile(d, '*.csv'));
        rmdir(d);
    catch
    end
end
