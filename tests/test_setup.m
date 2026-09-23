function test_setup()
% TEST_SETUP  The two copies of PsychImGuiSetup, and install and remove.
%
%   A release zip carries PsychImGuiSetup.m at its root, so that a fresh unzip
%   can call it with nothing on the path, and in m/, so that the helpers find
%   it later. A wrapper cannot replace one copy: it would call itself whenever
%   the package root is the current folder. The copies must stay identical.
%
%   Install and remove run against a scratch package in tempdir, so the path
%   of the suite itself never changes. Every path change here happens while
%   the MEX is not loaded, because a path change under a locked MEX sends
%   Octave 10.1 on Linux into endless recursion (SPEC.md section 14.6).
%   'remove' has to unload the MEX itself, and one check proves that it does.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    rootCopy = fullfile(root, 'PsychImGuiSetup.m');
    mCopy = fullfile(root, 'm', 'PsychImGuiSetup.m');

    %% the two copies
    t_ok('PsychImGuiSetup.m is at the package root', exist(rootCopy, 'file') ~= 0);
    t_ok('PsychImGuiSetup.m is in m/', exist(mCopy, 'file') ~= 0);
    if exist(rootCopy, 'file') == 0 || exist(mCopy, 'file') == 0
        return;
    end
    % Line endings can differ after a git checkout with autocrlf.
    a = strrep(fileread(rootCopy), sprintf('\r'), '');
    b = strrep(fileread(mCopy), sprintf('\r'), '');
    t_ok('the root and m/ copies of PsychImGuiSetup.m are identical', strcmp(a, b));
    if ~strcmp(a, b)
        fprintf(2, '        copy m/PsychImGuiSetup.m over PsychImGuiSetup.m\n');
    end

    %% a scratch package: both copies, the file that marks m/, no MEX
    % The copies get names of their own. With two files of one name, the
    % test would depend on which one the engine resolves, and Octave 6.4 and
    % Homebrew Octave keep calling a function they have already loaded from
    % the path even after cd into a folder with another file of that name.
    % Measured in WSL, Octave 6.4: after whoami() from folder a on the path,
    % cd into folder b still runs a's whoami. So the test called the real
    % PsychImGuiSetup, which has a MEX (no NotBuilt) and removed the real
    % package from the path. Unique names take the lookup out of the test;
    % the drift check above keeps the logic identical.
    rootName = 'pimgui_scratch_setup_root';
    mName = 'pimgui_scratch_setup_m';
    arch = PsychImGuiSetup('arch');
    pkg = tempname();
    mkdir(fullfile(pkg, 'm'));
    mkdir(fullfile(pkg, 'dist', arch));
    local_copy_renamed(rootCopy, fullfile(pkg, [rootName '.m']), rootName);
    local_copy_renamed(mCopy, fullfile(pkg, 'm', [mName '.m']), mName);
    copyfile(fullfile(root, 'm', 'PsychImGuiOpen.m'), fullfile(pkg, 'm'));

    % The suite left a context behind, so the MEX is locked. Unload it before
    % the first path change.
    PsychImGui('Shutdown', 'all');
    local_clear_mex();
    local_clear_fn(rootName, mName);     % stale copies from an earlier run
    t_ok('the MEX is unloaded before the scratch install', ~mislocked('PsychImGui'));

    old = pwd();
    p0 = path();
    try
        cd(pkg);
        % The directories as the Setup itself names them, from its own
        % mfilename. tempdir can sit behind a symbolic link, as /var ->
        % /private/var on macOS, so a name built here from tempname could
        % differ from the one the Setup puts on the path.
        pkgDist = feval(rootName, 'distdir');
        pkgRoot = fileparts(fileparts(pkgDist));
        pkgM = fullfile(pkgRoot, 'm');

        %% install, from the package root as the current folder
        threw = '';
        try
            feval(rootName);
        catch e
            threw = e.identifier;
        end
        t_eq('a package with no MEX raises psychimgui:NotBuilt', threw, 'psychimgui:NotBuilt');
        t_eq('the failed check leaves the path alone', path(), p0);

        feval(rootName, 'nocheck');
        cd(old);
        t_ok('install puts dist/<arch> on the path', local_index(pkgDist) > 0);
        t_ok('install puts m/ on the path', local_index(pkgM) > 0);
        t_ok('install puts dist/<arch> ahead of m/', local_index(pkgDist) < local_index(pkgM));
        t_ok('install leaves the package root off the path', local_index(pkgRoot) == 0);
        t_ok('the scratch m/ copy is reachable now', exist(mName, 'file') == 2);

        %% remove, through the m/ copy, with the MEX loaded and locked
        PsychImGui('Init', 0, [0 0 64 64], zeros(256, 1, 'int32'), ...
                   struct('renderer', 'none', 'iniFile', ''));
        t_ok('Init locks the MEX', mislocked('PsychImGui'));
        removed = feval(mName, 'remove');
        t_ok('remove reports a change', removed);
        t_ok('remove unloads the MEX first', ~mislocked('PsychImGui'));
        t_ok('remove takes dist/<arch> off the path', local_index(pkgDist) == 0);
        t_ok('remove takes m/ off the path', local_index(pkgM) == 0);
        t_eq('remove restores the path from before the install', path(), p0);

        %% a second remove, through the root copy, does nothing
        cd(pkg);
        removed = feval(rootName, 'remove');
        cd(old);
        t_ok('a second remove reports no change', ~removed);
        t_eq('a second remove leaves the path alone', path(), p0);
    catch e
        t_ok(sprintf('install and remove ran (%s: %s)', e.identifier, e.message), false);
    end

    % Whatever failed above, leave the folder and the path exactly as they
    % were, so the rest of the suite still finds the real package. The MEX
    % is unloaded first, as for every path change here.
    cd(old);
    if ~isequal(path(), p0)
        fprintf(2, '        test_setup: restoring the path it found\n');
        PsychImGui('Shutdown', 'all');
        local_clear_mex();
        path(p0);
    end
    local_clear_fn(rootName, mName);
    rmdir(pkg, 's');
end

function local_copy_renamed(src, dst, name)
    txt = fileread(src);
    head = 'function out = PsychImGuiSetup(';
    assert(strncmp(txt, head, numel(head)), 'test_setup:copy', ...
           'PsychImGuiSetup.m no longer starts with "%s"', head);
    txt = ['function out = ' name '(' txt(numel(head) + 1:end)];
    fid = fopen(dst, 'w');
    fwrite(fid, txt);
    fclose(fid);
end

function local_clear_mex()
    local_clear_fn('PsychImGui');
end

function local_clear_fn(varargin)
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        clear('-f', varargin{:});
    else
        clear(varargin{:});
    end
end

function idx = local_index(dir)
    entries = strsplit(path(), pathsep());
    idx = 0;
    for i = 1:numel(entries)
        if (ispc && strcmpi(entries{i}, dir)) || strcmp(entries{i}, dir)
            idx = i;
            return;
        end
    end
end
