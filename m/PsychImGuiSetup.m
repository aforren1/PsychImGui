function out = PsychImGuiSetup(mode)
% PsychImGuiSetup  Put the PsychImGui MEX for this platform on the path.
%
%   PsychImGuiSetup()              Add dist/<arch> and m/ to the path, dist
%                                  first, so the MEX shadows the help text in
%                                  m/PsychImGui.m. Errors when the MEX for this
%                                  platform is missing.
%   d = PsychImGuiSetup()          The same, and return the directory it added.
%   PsychImGuiSetup('nocheck')     Add the paths without requiring the MEX.
%   a = PsychImGuiSetup('arch')    Return the platform tag. Changes no path.
%   d = PsychImGuiSetup('distdir') Return dist/<arch>. Changes no path.
%
%   Octave names its MEX PsychImGui.mex on every operating system, so one flat
%   dist directory cannot hold a Windows build and a Linux build at the same
%   time: the second build silently replaces the first. Each platform gets its
%   own subdirectory instead, named the way computer('arch') names it in
%   MATLAB, so the two engines share a directory (their file extensions differ)
%   but two operating systems never do.
%
%   Errors with psychimgui:NotBuilt, naming the path it looked in and the
%   command that fills it, when this platform has no MEX yet.
%
%   See also PsychImGui, build.

    if nargin < 1
        mode = 'check';
    end
    if ~ischar(mode)
        error('psychimgui:Usage', 'PsychImGuiSetup takes a char mode.');
    end

    mdir = fileparts(mfilename('fullpath'));
    root = fileparts(mdir);
    arch = local_arch();
    distdir = fullfile(root, 'dist', arch);

    switch mode
        case 'arch'
            out = arch;
            return;
        case 'distdir'
            out = distdir;
            return;
        case {'check', 'nocheck'}
            % fall through
        otherwise
            error('psychimgui:Usage', ...
                  ['PsychImGuiSetup: unknown mode "%s". Use no argument, ' ...
                   '''nocheck'', ''arch'', or ''distdir''.'], mode);
    end

    if strcmp(mode, 'check')
        binary = fullfile(distdir, ['PsychImGui.' mexext]);
        if exist(binary, 'file') == 0
            error('psychimgui:NotBuilt', ...
                  ['The PsychImGui MEX for this platform is not built.\n' ...
                   '  expected: %s\n' ...
                   '  build it: cd(''%s''); build\n' ...
                   'Use the same engine you want to run it in.'], binary, root);
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

    if nargout > 0
        out = distdir;
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
    entries = strsplit(path(), pathsep());
    want = local_norm(dir);
    tf = false;
    for i = 1:numel(entries)
        if strcmp(local_norm(entries{i}), want)
            tf = true;
            return;
        end
    end
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
