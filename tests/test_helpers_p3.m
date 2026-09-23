function test_helpers_p3()
% TEST_HELPERS_P3  The helpers with several windows and with stereo.
%
%   Uses the recording Screen stub of tf_screen, like test_helpers. Checks
%   that each handle carries its own context and that the helpers switch to
%   it, that closing one window leaves the other open, and the exact sequence
%   of Screen calls PsychImGuiFrame('End') makes for a stereo window: leave
%   the region, then per eye SelectStereoDrawBuffer, BeginOpenGL, one
%   submission, EndOpenGL.

    if ~tf_screen('active')
        t_ok('the Screen stub is on the path (run this file through run_tests)', false);
        return;
    end
    ws = warning('off', 'psychimgui:NoKeyboard');
    PsychImGui('Shutdown', 'all');
    opts = struct('renderer', 'none', 'iniFile', '');

    %% two windows
    tf_screen('reset');
    igA = PsychImGuiOpen(11, opts);
    igB = PsychImGuiOpen(12, opts);
    t_ok('each Open returns a context handle', igA.ctx > 0 && igB.ctx > 0);
    t_ok('two windows get two contexts', igA.ctx ~= igB.ctx);
    t_eq('a mono window is not stereo', igA.stereo, false);

    igA = PsychImGuiFrame('Begin', igA);
    t_eq('Frame Begin switches to its context', PsychImGui('GetContext'), igA.ctx);
    PsychImGui('Begin', 'a');
    PsychImGui('End');
    PsychImGuiFrame('End', igA);
    igB = PsychImGuiFrame('Begin', igB);
    t_eq('Frame Begin of the other window switches back', PsychImGui('GetContext'), ...
         igB.ctx);
    PsychImGuiFrame('End', igB);

    PsychImGuiGL(igA, 'GetFrameCount');
    t_eq('PsychImGuiGL switches to its context', PsychImGui('GetContext'), igA.ctx);

    PsychImGuiClose(igA);
    [~, live] = PsychImGui('GetContext');
    t_eq('closing one window leaves the other', live, igB.ctx);

    tf_screen('reset');
    t_throws('Frame Begin with a closed handle', 'psychimgui:NotInit', ...
             @() PsychImGuiFrame('Begin', igA));
    t_eq('the refused Begin still left the region', tf_screen('gl'), ...
         {'BeginOpenGL', 'EndOpenGL'});
    t_throws('PsychImGuiGL with a closed handle', 'psychimgui:InvalidHandle', ...
             @() PsychImGuiGL(igA, 'GetFrameCount'));
    t_eq('PsychImGuiGL left 2D mode after the error', tf_screen('mode'), 0);
    igB = PsychImGuiClose(igB);
    t_ok('Close clears the handle', isempty(igB.ctx));
    [cur, live] = PsychImGui('GetContext');
    t_ok('no context is left', cur == 0 && isempty(live));

    %% stereo
    tf_screen('setstereo', 4);
    igS = PsychImGuiOpen(13, opts);
    t_eq('a stereo window is stereo', igS.stereo, true);
    igS = PsychImGuiFrame('Begin', igS);
    PsychImGui('Begin', 'both eyes');
    PsychImGui('Button', 'x');
    PsychImGui('End');
    tf_screen('reset');
    PsychImGuiFrame('End', igS);
    t_eq('Frame End draws both eyes', tf_screen('gl'), ...
         {'EndOpenGL', 'SelectStereoDrawBuffer0', 'BeginOpenGL', 'EndOpenGL', ...
          'SelectStereoDrawBuffer1', 'BeginOpenGL', 'EndOpenGL'});
    t_eq('Frame End of a stereo window left 2D mode', tf_screen('mode'), 0);
    s = PsychImGui('Stats');
    t_ok('the second eye went through RenderAgain', ...
         any(strcmp({s.perOp.name}, 'RenderAgain')));
    PsychImGuiClose(igS);

    igO = PsychImGuiOpen(14, setfield(opts, 'stereo', false)); %#ok<SFLD>
    t_eq('opts.stereo overrides the window', igO.stereo, false);
    igO = PsychImGuiFrame('Begin', igO);
    tf_screen('reset');
    PsychImGuiFrame('End', igO);
    t_eq('a mono override draws once', tf_screen('gl'), {'EndOpenGL'});
    PsychImGuiClose(igO);
    tf_screen('setstereo', 0);

    warning(ws);
end
