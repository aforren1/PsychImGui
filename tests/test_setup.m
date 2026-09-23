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
    arch = PsychImGuiSetup('arch');
    pkg = tempname();
    mkdir(fullfile(pkg, 'm'));
    mkdir(fullfile(pkg, 'dist', arch));
    copyfile(rootCopy, fullfile(pkg, 'PsychImGuiSetup.m'));
    copyfile(mCopy, fullfile(pkg, 'm', 'PsychImGuiSetup.m'));
    copyfile(fullfile(root, 'm', 'PsychImGuiOpen.m'), fullfile(pkg, 'm'));
    pkgDist = fullfile(pkg, 'dist', arch);
    pkgM = fullfile(pkg, 'm');

    % The suite left a context behind, so the MEX is locked. Unload it before
    % the first path change.
    PsychImGui('Shutdown', 'all');
    local_clear_mex();
    t_ok('the MEX is unloaded before the scratch install', ~mislocked('PsychImGui'));

    old = pwd();
    p0 = path();
    try
        %% install, from the package root as the current folder
        cd(pkg);
        threw = '';
        try
            PsychImGuiSetup();
        catch e
            threw = e.identifier;
        end
        t_eq('a package with no MEX raises psychimgui:NotBuilt', threw, 'psychimgui:NotBuilt');
        t_eq('the failed check leaves the path alone', path(), p0);

        PsychImGuiSetup('nocheck');
        cd(old);
        t_ok('install puts dist/<arch> on the path', local_index(pkgDist) > 0);
        t_ok('install puts m/ on the path', local_index(pkgM) > 0);
        t_ok('install puts dist/<arch> ahead of m/', local_index(pkgDist) < local_index(pkgM));
        t_ok('install leaves the package root off the path', local_index(pkg) == 0);
        t_eq('the scratch m/ copy answers now', which('PsychImGuiSetup'), ...
             fullfile(pkgM, 'PsychImGuiSetup.m'));

        %% remove, through the m/ copy, with the MEX loaded and locked
        PsychImGui('Init', 0, [0 0 64 64], zeros(256, 1, 'int32'), ...
                   struct('renderer', 'none', 'iniFile', ''));
        t_ok('Init locks the MEX', mislocked('PsychImGui'));
        removed = PsychImGuiSetup('remove');
        t_ok('remove reports a change', removed);
        t_ok('remove unloads the MEX first', ~mislocked('PsychImGui'));
        t_ok('remove takes dist/<arch> off the path', local_index(pkgDist) == 0);
        t_ok('remove takes m/ off the path', local_index(pkgM) == 0);
        t_eq('remove restores the path from before the install', path(), p0);

        %% a second remove, through the root copy, does nothing
        cd(pkg);
        removed = PsychImGuiSetup('remove');
        cd(old);
        t_ok('a second remove reports no change', ~removed);
        t_eq('a second remove leaves the path alone', path(), p0);
    catch e
        cd(old);
        t_ok(sprintf('install and remove ran (%s: %s)', e.identifier, e.message), false);
    end

    % A failure above can leave scratch entries behind. Take them off with the
    % MEX unloaded, as everywhere else.
    if local_index(pkgDist) > 0 || local_index(pkgM) > 0
        PsychImGui('Shutdown', 'all');
        local_clear_mex();
        path(p0);
    end
    rmdir(pkg, 's');
end

function local_clear_mex()
    if exist('OCTAVE_VERSION', 'builtin') ~= 0
        clear('-f', 'PsychImGui');
    else
        clear('PsychImGui');
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
