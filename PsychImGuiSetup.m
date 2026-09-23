function out = PsychImGuiSetup(mode, opt)
% PsychImGuiSetup  Put PsychImGui on the path, or take it off again.
%
%   PsychImGuiSetup                Add dist/<arch> and m/ to the path, dist
%                                  first, so the MEX shadows the help text in
%                                  m/PsychImGui.m. Errors when the MEX for
%                                  this platform is missing.
%   PsychImGuiSetup save           The same, then savepath, so later sessions
%                                  have it too.
%   d = PsychImGuiSetup()          Add, and return the dist/<arch> directory.
%   PsychImGuiSetup('nocheck')     Add the paths without requiring the MEX.
%   PsychImGuiSetup remove         Take dist/<arch>, m/, and this folder off
%                                  the path. Does nothing when none of them
%                                  is on the path.
%   PsychImGuiSetup remove save    The same, then savepath.
%   a = PsychImGuiSetup('arch')    Return the platform tag. Changes no path.
%   d = PsychImGuiSetup('distdir') Return dist/<arch>. Changes no path.
%
%   First use after you unzip a release, with nothing on the path yet:
%
%     addpath('C:\toolboxes\PsychImGui'); PsychImGuiSetup
%     run('C:\toolboxes\PsychImGui\PsychImGuiSetup.m')
%     cd C:\toolboxes\PsychImGui; PsychImGuiSetup
%
%   Octave names its MEX PsychImGui.mex on every operating system, so one flat
%   dist directory cannot hold a Windows build and a Linux build at the same
%   time: the second build silently replaces the first. Each platform gets its
%   own subdirectory instead, named the way computer('arch') names it in
%   MATLAB, so the two engines share a directory (their file extensions differ)
%   but two operating systems never do.
%
%   Errors with psychimgui:NotBuilt, naming the path it looked in and what
%   fills it, when this platform has no MEX. 'remove' first shuts down every
%   context and unloads the MEX, because a path change while the MEX is
%   locked crashes Octave 10.1 on Linux. When the MEX stays loaded, it warns
%   with psychimgui:StillLoaded and leaves the path alone.
%
%   See also PsychImGui, PsychImGuiOpen.

    % This file ships twice, byte for byte: at the package root, so that a
    % fresh unzip can call it before anything is on the path, and in m/, so
    % that the helpers find it once m/ is on the path. A root wrapper that
    % called the m/ copy by name would call itself, because a function that
    % calls its own name recurses and the current folder comes first in the
    % lookup. tests/test_setup checks that the two copies stay identical.
    here = fileparts(mfilename('fullpath'));
    if exist(fullfile(here, 'm', 'PsychImGuiOpen.m'), 'file') ~= 0
        root = here;
    else
        root = fileparts(here);
    end

    if nargin < 1 || isempty(mode)
        mode = 'check';
    end
    if nargin < 2
        opt = '';
    end
    if ~ischar(mode) || ~ischar(opt)
        error('psychimgui:Usage', 'PsychImGuiSetup takes char arguments.');
    end
    if strcmp(mode, 'save')
        mode = 'check';
        opt = 'save';
    end
    if ~isempty(opt) && ~strcmp(opt, 'save')
        error('psychimgui:Usage', ...
              'PsychImGuiSetup: the second argument can only be ''save''.');
    end
    doSave = ~isempty(opt);

    mdir = fullfile(root, 'm');
    arch = local_arch();
    distdir = fullfile(root, 'dist', arch);

    switch mode
        case 'arch'
            out = arch;
            return;
        case 'distdir'
            out = distdir;
            return;
        case 'remove'
            changed = local_remove({distdir, mdir, root});
            if doSave && changed >= 0
                local_save();
            end
            if nargout > 0
                out = changed > 0;
            end
            return;
        case {'check', 'nocheck'}
            % fall through
        otherwise
            error('psychimgui:Usage', ...
                  ['PsychImGuiSetup: unknown mode "%s". Use no argument, ' ...
                   '''save'', ''nocheck'', ''remove'', ''arch'', or ''distdir''.'], ...
                  mode);
    end

    if strcmp(mode, 'check')
        binary = fullfile(distdir, ['PsychImGui.' mexext]);
        if exist(binary, 'file') == 0
            if exist(fullfile(root, 'build.m'), 'file') ~= 0
                how = sprintf('  build it: cd(''%s''); build\n', root);
            else
                % A release zip has no build.m. The usual cause is a zip for
                % another engine or operating system.
                how = sprintf(['  get it:   download the release zip for ' ...
                               'this engine and platform (%s)\n'], arch);
            end
            error('psychimgui:NotBuilt', ...
                  ['The PsychImGui MEX for this platform is not built.\n' ...
                   '  expected: %s\n%s' ...
                   'Use the same engine you want to run it in.'], binary, how);
        end
    end

    % m/ first, then dist in front of it. addpath prepends, so the directory
    % added last wins the name PsychImGui. Both calls are skipped when the
    % path is already right: PsychImGuiOpen calls this on every open, and a
    % load path change while the locked MEX is loaded sends Octave 10.1 on
    % Linux into endless recursion (SPEC.md section 14.6). addpath of a
    % directory that is already present still counts as a change there.
    %
    % "Already right" has to mean the order, not just the presence. Another
    % script that does addpath(fullfile(root, 'm')) puts the help text in
    % m/PsychImGui.m ahead of the MEX, and leaving that alone would make every
    % later PsychImGui call raise psychimgui:NotBuilt.
    if ~local_dist_wins(distdir, mdir)
        if ~local_on_path(mdir)
            addpath(mdir);
        end
        addpath(distdir, '-begin');
    end
    if doSave
        local_save();
    end

    if nargout > 0
        out = distdir;
    end
end

function changed = local_remove(dirs)
% Returns the number of path entries removed, or -1 when the MEX could not be
% unloaded and the path was left alone.
    entries = strsplit(path(), pathsep());
    hits = {};
    for i = 1:numel(dirs)
        k = local_index(entries, dirs{i});
        if k > 0
            hits{end+1} = entries{k}; %#ok<AGROW>
        end
    end
    changed = numel(hits);
    if changed == 0
        return;     % not on the path: nothing to unload, nothing to change
    end

    % The order is the point: every context shut down, so the MEX unlocks,
    % then the MEX cleared, and only then the path changed. Octave 10.1 on
    % Linux recurses without end when the path changes under a locked MEX
    % (SPEC.md section 14.6).
    if local_locked()
        try
            PsychImGui('Shutdown', 'all');
        catch
            % Reported below if the MEX is still locked.
        end
    end
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        clear('-f', 'PsychImGui');
    else
        clear('PsychImGui');
    end
    if local_locked()
        warning('psychimgui:StillLoaded', ...
                ['PsychImGui is still loaded, so the path was not changed.\n' ...
                 'Close your Psychtoolbox windows with sca, run ' ...
                 'PsychImGui(''Shutdown'', ''all''), then run ' ...
                 'PsychImGuiSetup remove again. If that fails, restart ' ...
                 'MATLAB or Octave and run it before anything else.']);
        changed = -1;
        return;
    end

    for i = 1:numel(hits)
        rmpath(hits{i});
    end
end

function tf = local_locked()
    try
        tf = mislocked('PsychImGui');
    catch
        tf = false;
    end
end

function local_save()
    if savepath() ~= 0
        warning('psychimgui:SavePath', ...
                ['savepath could not write the path file. Put the ' ...
                 'PsychImGuiSetup call in your startup.m (MATLAB) or ' ...
                 '~/.octaverc (Octave) instead.']);
    end
end

function a = local_arch()
    if exist('OCTAVE_VERSION', 'builtin') == 0
        a = computer('arch');       % MATLAB already uses these names
        return;
    end
    % Octave answers computer('arch') with a GNU triplet, such as
    % mingw32-x86_64 or gnu-linux-x86_64, so derive the MATLAB name instead.
    if ispc
        a = 'win64';
    elseif ismac
        m = lower([computer('arch') ' ' computer()]);
        if ~isempty(strfind(m, 'aarch64')) || ~isempty(strfind(m, 'arm64')) %#ok<STREMP>
            a = 'maca64';
        else
            a = 'maci64';
        end
    else
        a = 'glnxa64';
    end
end

function tf = local_dist_wins(distdir, mdir)
% True when dist/<arch> is on the path and nothing in m/ can shadow it, which
% is the only state this function has to leave behind.
    entries = strsplit(path(), pathsep());
    iDist = local_index(entries, distdir);
    iM = local_index(entries, mdir);
    tf = iDist > 0 && (iM == 0 || iDist < iM);
end

function idx = local_index(entries, dir)
    want = local_norm(dir);
    idx = 0;
    for i = 1:numel(entries)
        if strcmp(local_norm(entries{i}), want)
            idx = i;
            return;
        end
    end
end

function tf = local_on_path(dir)
% Path entries are compared as normalized absolute directory names. Windows
% file systems are case insensitive, so the comparison is too there.
    tf = local_index(strsplit(path(), pathsep()), dir) > 0;
end

function s = local_norm(dir)
    s = strrep(dir, '/', filesep);
    while numel(s) > 1 && s(end) == filesep
        s = s(1:end-1);
    end
    if ispc
        s = lower(s);
    end
end
