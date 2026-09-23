function build(varargin)
% BUILD  Compile the PsychImGui MEX for MATLAB or Octave.
%
%   build            Build the static library with CMake, then the MEX.
%   build gen        Run the binding generator first, then build.
%   build test       Build, then run the test suite.
%   build clean      Remove the build and install directories of this engine.
%
%   The two engines use different compilers on Windows (MSVC for MATLAB, MinGW
%   g++ for Octave), and C++ objects from different compilers must not be
%   linked together, so each engine gets its own build directory.
%
%   Set MEX_CMAKE_GENERATOR to override the CMake generator.
%
%   Set PSYCHIMGUI_TRACY=1 to compile the Tracy profiler client into the
%   library and its zones into the MEX (SPEC.md section 9.3). Tracy is not
%   fetched with the other dependencies; clone it first:
%
%       git clone --branch v0.11.1 https://github.com/wolfpld/tracy.git third_party/tracy

    here = fileparts(mfilename('fullpath'));
    old = cd(here);
    restore = onCleanup(@() cd(old));

    is_octave = exist('OCTAVE_VERSION', 'builtin') ~= 0;
    % One directory per engine and platform. The two engines use different
    % compilers, and one checkout can be shared between Windows and WSL or a
    % network home directory, so object files from four toolchains must never
    % meet in one build tree.
    if is_octave
        engine = 'octave';
    else
        engine = 'matlab';
    end
    builddir = ['build-' engine '-' platform_tag()];
    instdir  = ['inst-' engine '-' platform_tag()];

    do_gen = false; do_test = false;
    for i = 1:numel(varargin)
        switch lower(varargin{i})
            case 'gen',   do_gen = true;
            case 'test',  do_test = true;
            case 'clean'
                if exist(builddir, 'dir'); rmdir(builddir, 's'); end
                if exist(instdir, 'dir');  rmdir(instdir, 's');  end
                fprintf('removed %s and %s\n', builddir, instdir);
                return;
            otherwise
                error('build:usage', 'Unknown option "%s".', varargin{i});
        end
    end

    if do_gen
        uv = find_uv();
        run_cmd(sprintf('"%s" run --project gen python gen/generate.py', uv));
    end

    check_third_party(here);
    tracy = tracy_enabled();
    if tracy
        check_tracy(here);
        tracyFlag = 'ON';
    else
        tracyFlag = 'OFF';
    end

    % --- the static library ---------------------------------------------
    if ~exist(builddir, 'dir'); mkdir(builddir); end
    % The Tracy option is always passed, so a build directory configured for
    % Tracy once does not keep linking the profiler into later builds.
    cfg = ['cmake -E chdir ' builddir ' cmake ' ...
           '-DCMAKE_BUILD_TYPE=Release ' ...
           '-DCMAKE_INSTALL_PREFIX=../' instdir ' ' ...
           '-DPSYCHIMGUI_TRACY=' tracyFlag ' -DPSYCHIMGUI_STATS=1 ' ...
           '-DPSYCHIMGUI_IMPLOT=ON -DPSYCHIMGUI_IMPLOT3D=ON -DPSYCHIMGUI_FILEDIALOG=ON '];

    gen = getenv('MEX_CMAKE_GENERATOR');
    if ~isempty(gen)
        cfg = [cfg '-G "' gen '" '];
    elseif ispc && is_octave
        % Octave on Windows ships an MSYS2 environment with a MinGW g++. The
        % "MinGW Makefiles" generator refuses to run while sh.exe is on PATH,
        % and Git for Windows keeps one there, so use the MSYS generator. Its
        % make lives in Octave's usr/bin, which Octave does not put on PATH.
        cfg = [cfg '-G "MSYS Makefiles" '];
    elseif ispc
        cfg = [cfg '-G "Visual Studio 17 2022" -A x64 '];
    end
    if is_octave && ispc
        % With a generator override (MSYS2 CI uses Ninja) CMake finds its own
        % build program, and naming make would break the Ninja generator.
        cfg = [cfg octave_toolchain_flags(isempty(gen))];
    elseif is_octave
        % mkoctfile -p CXX may answer with flags attached, for example
        % "clang++ -std=gnu++17" from Homebrew Octave on macOS. CMake wants
        % the program alone in CMAKE_CXX_COMPILER; the rest goes to the flags.
        cxx = strtrim(oct_prog('CXX'));
        if ~isempty(cxx)
            parts = strsplit(cxx);
            cfg = [cfg '-DCMAKE_CXX_COMPILER="' resolve_compiler(parts{1}) '" '];
            if numel(parts) > 1
                cfg = [cfg '-DCMAKE_CXX_FLAGS="' strjoin(parts(2:end), ' ') '" '];
            end
        end
    end
    cfg = [cfg '..'];

    % A build directory left over from another generator makes cmake refuse to
    % reconfigure; wipe it and try once more.
    if system(cfg) ~= 0
        fprintf('cmake configure failed; wiping %s and retrying...\n', builddir);
        rmdir(builddir, 's');
        mkdir(builddir);
        run_cmd(cfg);
    end
    run_cmd(['cmake --build ' builddir ' --config Release']);
    run_cmd(['cmake --build ' builddir ' --target install --config Release']);

    % --- locate the installed static library ------------------------------
    if ispc && ~is_octave
        libfile = fullfile(instdir, 'lib', 'imgui_static.lib');
    else
        libfile = fullfile(instdir, 'lib', 'libimgui_static.a');
    end
    assert(exist(libfile, 'file') ~= 0, 'build:lib', ...
           'static library not found: %s', libfile);

    % --- the MEX ----------------------------------------------------------
    % No -R2018a: the code uses only the classic mx* API, so one source builds
    % for both engines.
    %
    % One dist subdirectory per platform. Octave calls its MEX PsychImGui.mex
    % on every operating system, so a flat dist would let a Linux build replace
    % a Windows one in a shared checkout. PsychImGuiSetup names the directory.
    addpath(fullfile(here, 'm'));
    arch = PsychImGuiSetup('arch');
    outdir = fullfile('dist', arch);
    if ~exist(outdir, 'dir'); mkdir(outdir); end
    imgui_inc = fullfile('third_party', 'cimgui', 'imgui');
    implot_inc = fullfile('third_party', 'cimplot', 'implot');
    implot3d_inc = fullfile('third_party', 'cimplot3d', 'implot3d');
    igfd_inc = fullfile('third_party', 'ImGuiFileDialog');

    args = { ['-I' imgui_inc], ['-I' fullfile(imgui_inc, 'backends')], ...
             ['-I' implot_inc], ['-I' implot3d_inc], ['-I' igfd_inc], '-Isrc', ...
             '-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS', ...
             '-DPSYCHIMGUI_IMPLOT', '-DPSYCHIMGUI_IMPLOT3D', '-DPSYCHIMGUI_FILEDIALOG', ...
             '-DPSYCHIMGUI_STATS=1' };
    if tracy
        % The same definitions as the library (CMakeLists.txt), or the MEX and
        % the core would disagree about the profiler's lifetime.
        args = [args, {['-I' fullfile('third_party', 'tracy', 'public')], ...
                       '-DTRACY_ENABLE', '-DTRACY_DELAYED_INIT', ...
                       '-DTRACY_MANUAL_LIFETIME', '-DTRACY_NO_CRASH_HANDLER', ...
                       '-DPSYCHIMGUI_TRACY'}];
    end
    if is_octave
        args{end+1} = '-DPSYCHIMGUI_OCTAVE';
    end
    if ismac
        % Apple deprecated OpenGL in 10.14. It still works, and it is the only
        % thing Psychtoolbox draws with, so quiet the warning rather than have
        % it on every source file.
        args{end+1} = '-DGL_SILENCE_DEPRECATION';
    end
    % C++17 reaches the compiler differently per engine. Octave's mex rejects
    % a FLAGS=value argument and takes mkoctfile's flags from the environment
    % instead, so set CXXFLAGS around the call and put it back afterwards.
    envGuard = []; %#ok<NASGU>  keeps the restore alive until build returns
    ldGuard = []; %#ok<NASGU>
    if is_octave
        oldCxxFlags = getenv('CXXFLAGS');
        base = strtrim(oct_prog('CXXFLAGS'));
        setenv('CXXFLAGS', [base ' -std=c++17']);
        envGuard = onCleanup(@() setenv('CXXFLAGS', oldCxxFlags));
        if ismac
            % mkoctfile takes its link flags from the environment too, and a
            % framework cannot be named with -l.
            oldLdFlags = getenv('LDFLAGS');
            setenv('LDFLAGS', [strtrim(oct_prog('LDFLAGS')) ' -framework OpenGL']);
            ldGuard = onCleanup(@() setenv('LDFLAGS', oldLdFlags));
        end
    elseif ispc
        args{end+1} = 'COMPFLAGS=$COMPFLAGS /std:c++17 /EHsc';
    else
        args{end+1} = 'CXXFLAGS=$CXXFLAGS -std=c++17';
        % ImGuiFileDialog uses the standard containers, and GCC 11's headers
        % make every std::vector call std::__throw_bad_array_new_length,
        % a GLIBCXX_3.4.29 symbol. MATLAB R2021b, the Linux floor, bundles
        % an older libstdc++ and refuses to load the MEX (CI run 35863090083),
        % so the MATLAB MEX carries its own copy of the runtime. Octave links
        % against the system library its own binary uses, and needs nothing.
        args{end+1} = 'LDFLAGS=$LDFLAGS -static-libstdc++';
    end

    sources = { fullfile('src', 'psychimgui.cpp'), ...
                fullfile('src', 'filedialog.cpp'), ...
                fullfile('src', 'gen_dispatch.cpp'), ...
                fullfile('src', 'gen_dispatch_implot.cpp'), ...
                fullfile('src', 'gen_dispatch_implot3d.cpp') };

    if ispc
        gllib = {'-lopengl32'};
    elseif ismac
        % Octave already has the framework in LDFLAGS above; its mex rejects a
        % FLAGS=value argument.
        if is_octave
            gllib = {};
        else
            % The framework goes through LINKLIBS, not LDFLAGS. The first
            % macOS CI run linked with `LDFLAGS=$LDFLAGS -framework OpenGL`
            % and failed on undefined _mexFunctionAdapter, _mexCreateMexFunction
            % and _mexDestroyMexFunction, the C++ MEX Data API entry points,
            % which means the export list MATLAB chose no longer matched a
            % classic mexFunction file. Appending to the library list leaves
            % MATLAB's own LDFLAGS, and with them its export list, untouched.
            % The mex -v log from the macOS runner showed the cause: MATLAB's
            % clang++ configuration appends LINKEXPORTCPP for every C++ MEX
            % file. That is -Wl,-U for the three C++ Data API entry points plus
            % -exported_symbols_list cppMexFunction.map, on top of the classic
            % mexFunction.map. The classic ld64 tolerated the undefined exports
            % because of -U; the linker in Xcode 26 does not and reports them
            % as <initial-undefines>. This is a classic mexFunction file, so the
            % C++ export set is simply wrong for it and is cleared here.
            gllib = {'LINKLIBS=$LINKLIBS -framework OpenGL', 'LINKEXPORTCPP='};
            if ~isempty(getenv('CI'))
                % Nobody here has a Mac. The verbose link line in the CI log
                % is the only way to see what mex did.
                args = [{'-v'}, args];
            end
        end
    else
        % -ldl for the backend's dlopen based GL loader. Harmless on glibc 2.34
        % and newer, where libdl folded into libc, and required before that.
        gllib = {'-lGL', '-ldl'};
    end

    if tracy
        % The Tracy client talks over sockets and walks call stacks. MSVC picks
        % these libraries up from the client's own pragmas; MinGW and the
        % Unix linkers need them named.
        if ispc
            gllib = [gllib, {'-lws2_32', '-ldbghelp', '-ladvapi32', '-luser32'}];
        elseif ~ismac
            gllib = [gllib, {'-lpthread'}];
        end
    end

    mexargs = [args, sources, {libfile}, gllib, ...
               {'-output', fullfile(outdir, 'PsychImGui')}];
    mex(mexargs{:});

    fprintf('build complete: %s\n', ...
            fullfile(here, outdir, ['PsychImGui.' mexext]));

    if do_test
        addpath(fullfile(here, 'tests'));
        run_tests();
    end
end

function check_third_party(here)
% CMake refuses too, but only after the configure step, with the message
% buried in its log. This names the fix first.
    need = {fullfile('cimgui', 'imgui', 'imgui.cpp'), ...
            fullfile('cimplot', 'implot', 'implot.cpp'), ...
            fullfile('cimplot3d', 'implot3d', 'implot3d.cpp'), ...
            fullfile('ImGuiFileDialog', 'ImGuiFileDialog.cpp')};
    for i = 1:numel(need)
        if ~exist(fullfile(here, 'third_party', need{i}), 'file')
            error('build:thirdParty', ...
                  ['third_party/%s is missing. Run\n' ...
                   '    git submodule update --init --recursive\n' ...
                   'or, in a checkout without submodules,\n' ...
                   '    bash tools/fetch_third_party.sh\n' ...
                   'See third_party/PINS.md.'], strrep(need{i}, '\', '/'));
        end
    end
end

function tf = tracy_enabled()
    v = lower(strtrim(getenv('PSYCHIMGUI_TRACY')));
    tf = any(strcmp(v, {'1', 'on', 'true', 'yes'}));
end

function check_tracy(here)
    if exist(fullfile(here, 'third_party', 'tracy', 'public', 'TracyClient.cpp'), 'file')
        return;
    end
    error('build:tracy', ['PSYCHIMGUI_TRACY is set but Tracy is missing. Run\n' ...
        '    git clone --branch v0.11.1 https://github.com/wolfpld/tracy.git third_party/tracy\n' ...
        'or unset PSYCHIMGUI_TRACY. See third_party/PINS.md.']);
end

function tag = platform_tag()
    if ispc
        tag = 'windows';
    elseif ismac
        tag = 'mac';
    else
        tag = 'linux';
    end
end

function run_cmd(cmd)
    status = system(cmd);
    assert(status == 0, 'build:cmd', 'command failed (status %d): %s', status, cmd);
end

function flags = octave_toolchain_flags(want_make)
% Point CMake at Octave's own MinGW toolchain by absolute path.
%
%   Octave puts mingw64/bin on PATH but not usr/bin, so CMake finds neither
%   make nor, reliably, the binutils that match the bundled g++. Naming them
%   here keeps the static archive link compatible with mkoctfile.

    home = OCTAVE_HOME();                    % ...\Octave-x.y.z\mingw64
    root = fileparts(home);                  % ...\Octave-x.y.z
    bin = fullfile(home, 'bin');

    flags = '';
    flags = [flags tool_flag('CMAKE_CXX_COMPILER', fullfile(bin, 'g++.exe'))];
    flags = [flags tool_flag('CMAKE_C_COMPILER', fullfile(bin, 'gcc.exe'))];
    flags = [flags tool_flag('CMAKE_AR', fullfile(bin, 'ar.exe'))];
    flags = [flags tool_flag('CMAKE_RANLIB', fullfile(bin, 'ranlib.exe'))];
    if want_make
        flags = [flags tool_flag('CMAKE_MAKE_PROGRAM', ...
                                 fullfile(root, 'usr', 'bin', 'make.exe'))];
    end
end

function f = tool_flag(name, path)
    if exist(path, 'file')
        f = ['-D' name '="' strrep(path, '\', '/') '" '];
    else
        f = '';
    end
end

function s = oct_prog(what)
    % mkoctfile -p reports the toolchain Octave itself was built with.
    [st, s] = system(['mkoctfile -p ' what]);
    if st ~= 0
        s = '';
    end
end

function p = resolve_compiler(cxx)
    % mkoctfile reports a bare program name; CMake wants a path it can test.
    cxx = strtrim(cxx);
    if ~ispc || any(cxx == filesep) || any(cxx == '/')
        p = cxx;
        return;
    end
    [st, out] = system(['where ' cxx]);
    if st == 0
        lines = strsplit(strtrim(out), sprintf('\n'));
        p = strrep(strtrim(lines{1}), '\', '/');
    else
        p = cxx;
    end
end

function uv = find_uv()
    cands = {'uv', fullfile(getenv('USERPROFILE'), '.local', 'bin', 'uv.exe'), ...
             fullfile(getenv('HOME'), '.local', 'bin', 'uv')};
    for i = 1:numel(cands)
        if i == 1
            [st, ~] = system('uv --version');
            if st == 0; uv = 'uv'; return; end
        elseif exist(cands{i}, 'file')
            uv = cands{i};
            return;
        end
    end
    error('build:uv', 'uv not found. The generator needs it; see README.md.');
end
