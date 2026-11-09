import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_voice/whisper_voice.dart';

import '../../data/providers.dart';
import '../../ui/browser_commands.dart';
import '../../ui/browser_theme.dart';
import '../settings/app_settings.dart';
import '../tabs/tabs_controller.dart';
import 'page_scroll.dart';
import 'search_results.dart';
import 'speech_input.dart';
import 'voice_commands.dart';
import 'whisper_models.dart';

/// Speech to text on this platform, or null where voice commands are not
/// available (then there is no microphone button). Overridden in tests.
final speechInputProvider = Provider<SpeechInput?>((ref) {
  if (kIsWeb) return null;
  final SpeechInput input;
  if (Platform.isWindows) {
    input = WhisperSpeechInput(
      WhisperVoice(),
      () => ref
          .read(whisperModelsProvider)
          .fileOf(ref.read(appSettingsProvider).voiceModel),
    );
  } else if (Platform.isAndroid) {
    input = AndroidSpeechInput();
  } else {
    return null;
  }
  ref.onDispose(input.cancel);
  return input;
});

/// True where speech runs on a downloaded Whisper model (Windows).
final usesWhisperModelsProvider = Provider<bool>(
  (ref) => !kIsWeb && Platform.isWindows,
);

/// Voice commands are on: the dock in the corner of the window listens,
/// carries out what is said and listens again, until it is closed.
final voiceModeProvider = NotifierProvider<VoiceMode, bool>(VoiceMode.new);

class VoiceMode extends Notifier<bool> {
  @override
  bool build() => false;

  void start() => state = true;
  void stop() => state = false;
}

/// The microphone buttons and the shortcut: voice commands on, or off when
/// they are on. Nothing where voice commands are not available.
void toggleVoiceCommands(WidgetRef ref) {
  if (ref.read(speechInputProvider) == null) return;
  final mode = ref.read(voiceModeProvider.notifier);
  ref.read(voiceModeProvider) ? mode.stop() : mode.start();
}

/// The microphone button: in the address bar on every page. It turns voice
/// commands on and off, and is filled while they are on. Nothing where
/// voice commands are not available.
class VoiceMicButton extends ConsumerWidget {
  const VoiceMicButton({
    super.key,
    required this.color,
    this.showShortcut = false,
    this.size = 14,
    this.width = 28,
    this.height = 26,
  });

  final Color color;

  /// Ctrl+Shift+Space in the tooltip (where there is a keyboard).
  final bool showShortcut;
  final double size;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(speechInputProvider) == null) return const SizedBox.shrink();
    final on = ref.watch(voiceModeProvider);
    final shortcut = showShortcut
        ? ' (${shortcutFor(BrowserCommand.voiceCommand)})'
        : '';
    return IconButton(
      tooltip: on
          ? 'Turn off voice commands$shortcut'
          : 'Voice commands$shortcut',
      iconSize: size,
      color: on ? Theme.of(context).colorScheme.primary : color,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: width, height: height),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(on ? CupertinoIcons.mic_fill : CupertinoIcons.mic),
      onPressed: () => toggleVoiceCommands(ref),
    );
  }
}

enum _Phase {
  /// Not listening: about to start, or paused while 6browser is minimized
  /// or a page or menu covers it.
  idle,

  /// Waiting for the speech model folder to be checked (Windows).
  starting,
  download,
  listening,
  recognizing,

  /// Stopped by an error; the microphone tries again.
  stopped,
}

/// The voice commands dock, in the bottom right corner of the page while
/// voice commands are on. It listens all the time: each command is carried
/// out in the selected tab and then it listens for the next one, until it
/// is closed (or told "stop listening"). It pauses while 6browser is
/// minimized or a page, dialog or menu is open over the browser.
///
/// In English, Persian and Danish only commands are carried out; other
/// words (a video playing, people talking in the room) are not searched
/// for. In other languages, where commands are not understood, what is
/// said is searched for.
class VoiceDock extends ConsumerStatefulWidget {
  const VoiceDock({super.key, required this.run});

  /// Runs browser commands (back, new tab...).
  final void Function(BrowserCommand command) run;

  @override
  ConsumerState<VoiceDock> createState() => _VoiceDockState();
}

class _VoiceDockState extends ConsumerState<VoiceDock> {
  late final SpeechInput? _input = ref.read(speechInputProvider);
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<SpeechEvent>? _session;
  _Phase _phase = _Phase.idle;
  SpeechError? _error;
  double _level = 0;

  /// Words recognized so far (Android shows them as they come).
  String _partial = '';

  /// The last thing said, and what came of it: [_note] says why nothing
  /// was done; [_done] when it was.
  String? _heard;
  String? _note;
  bool _done = false;

  /// A language picked in the dock, until the settings have it; and the
  /// one the current session listens in.
  VoiceLanguage? _picked;
  VoiceLanguage? _listeningIn;
  VoiceLanguage get _language =>
      _picked ?? ref.read(appSettingsProvider).voiceLanguage;

  /// 6browser is on screen, and no page, dialog or menu covers the
  /// browser.
  bool _visible = true;
  ModalRoute<Object?>? _route;
  bool get _front => _route?.isCurrent ?? true;
  bool get _wanted => _visible && _front;

  /// "Didn't catch that" right after starting, in a row: then it stops
  /// instead of starting over and over.
  DateTime _startedAt = DateTime(0);
  int _quickMisses = 0;

  @override
  void initState() {
    super.initState();
    _visible = _onScreen(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _visible = _onScreen(state);
        _sync();
      },
    );
  }

  /// Minimized or hidden: not on screen. Another window being in front
  /// ("inactive") is not enough to pause.
  static bool _onScreen(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Called again when a page, dialog or menu opens over the browser or
    // closes.
    _route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _session?.cancel();
    _input?.cancel();
    super.dispose();
  }

  /// Listens when it should and is not yet; pauses when it should not.
  void _sync() {
    if (!mounted) return;
    if (_wanted) {
      if (_phase == _Phase.idle) _listen();
      return;
    }
    if (_phase case _Phase.starting || _Phase.listening || _Phase.recognizing) {
      _session?.cancel();
      _session = null;
      _input?.cancel();
      _set(_Phase.idle);
    } else {
      setState(() {}); // shows "Paused"
    }
  }

  bool get _modelMissing {
    if (!ref.read(usesWhisperModelsProvider)) return false;
    final model = ref.read(appSettingsProvider).voiceModel;
    return ref.read(whisperModelsProvider).fileOf(model) == null;
  }

  void _listen() {
    final input = _input;
    if (input == null || !mounted) return;
    _session?.cancel();
    _session = null;
    if (!_wanted) return _set(_Phase.idle);
    if (ref.read(usesWhisperModelsProvider) &&
        ref.read(whisperModelsProvider).folder == null) {
      return _set(_Phase.starting); // the model folder is being checked
    }
    if (_modelMissing) return _set(_Phase.download);
    _set(_Phase.listening);
    _startedAt = DateTime.now();
    final language = _listeningIn = _language;
    _session = input.listen(language).listen(_onEvent);
  }

  void _pick(VoiceLanguage language) {
    _picked = language;
    ref.read(databaseProvider).setSetting('voiceLanguage', language.code);
    // The picker paused listening; otherwise start over in [language].
    if (_phase == _Phase.listening) _listen();
  }

  void _set(_Phase phase, {SpeechError? error}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _error = error;
      _level = 0;
      _partial = '';
    });
  }

  void _onEvent(SpeechEvent event) {
    if (!mounted) return;
    switch (event) {
      case SpeechLevel(:final level):
        setState(() => _level = level);
      case SpeechPartial(:final text):
        setState(() => _partial = text);
      case SpeechRecognizing():
        _set(_Phase.recognizing);
      case SpeechResult(:final text):
        _quickMisses = 0;
        _onSpeech(text);
      case SpeechFailed(:final error):
        _onFailure(error);
    }
  }

  Future<void> _onSpeech(String text) async {
    final settings = ref.read(appSettingsProvider);
    final language = _listeningIn ?? _language;
    final action = parseVoiceCommand(
      text,
      searchTemplate: settings.searchTemplate,
      searchFreeText: !commandLanguages.contains(language.code),
    );
    setState(() {
      _heard = text;
      _note = null;
      _done = false;
    });
    if (action is VoiceStopListening) {
      ref.read(voiceModeProvider.notifier).stop();
      return;
    }
    final note = action == null
        ? _notACommand(language)
        : await _perform(action);
    if (!mounted) return;
    setState(() {
      _note = note;
      _done = note == null;
    });
    _listen();
  }

  void _onFailure(SpeechError error) {
    switch (error) {
      case SpeechError.modelMissing:
        _set(_Phase.download);
      case SpeechError.noSpeech:
        // Silence: listen again, unless it keeps failing at once.
        final quick =
            DateTime.now().difference(_startedAt) <
            const Duration(milliseconds: 1500);
        _quickMisses = quick ? _quickMisses + 1 : 0;
        if (_quickMisses >= 3) {
          _quickMisses = 0;
          _set(_Phase.stopped, error: error);
        } else {
          _listen();
        }
      default:
        _set(_Phase.stopped, error: error);
    }
  }

  /// Carries out [action] in the selected tab. Returns why nothing was
  /// done, or null when it was.
  Future<String?> _perform(VoiceAction action) async {
    final tabs = ref.read(tabsProvider.notifier);
    final view = ref.read(tabsProvider).active?.view;
    void open(String url, {required bool newTab}) {
      if (newTab || view == null) {
        tabs.newTab(url: url, incognito: view?.incognito ?? false);
      } else {
        view.load(url);
      }
    }

    switch (action) {
      case VoiceStopListening():
        ref.read(voiceModeProvider.notifier).stop();
      case VoiceNavigate(:final url, :final newTab):
        open(url, newTab: newTab);
      case VoiceRunCommand(:final command):
        widget.run(command);
      case VoiceScroll(:final move):
        if (view == null) return null;
        final reply = await askPage(
          view,
          (token, post) => scrollPageScript(move, token: token, post: post),
        );
        if (reply == null) {
          return 'The page did not answer. Try again once it has loaded.';
        }
        if (reply['moved'] == false) {
          return move == ScrollMove.down || move == ScrollMove.bottom
              ? 'This is the end of the page.'
              : 'This is the top of the page.';
        }
      case VoiceOpenResult(:final number, :final newTab):
        if (view == null) return _searchFirst;
        switch (await findResult(view, number)) {
          case ResultFound(:final url):
            open(url, newTab: newTab);
          case ResultMissing(:final count):
            return count == 0
                ? 'No results found on this page.'
                : 'There is no result $number here: this page shows $count.';
          case NotResultsPage():
            return _searchFirst;
          case PageSilent():
            return 'The page did not answer. Try again once it has loaded.';
        }
      case VoiceResultsPage(:final step, :final number, :final otherwise):
        final url = view?.url.value ?? '';
        final site = SearchSite.of(url);
        if (view == null || site == null) {
          if (otherwise != null) {
            widget.run(otherwise);
            return null;
          }
          return 'This is not a page of search results.';
        }
        if (site == SearchSite.duckDuckGo && number == null && step > 0) {
          final reply = await askPage(
            view,
            (token, post) => moreResultsScript(token: token, post: post),
          );
          return reply?['more'] == true ? null : 'There are no more results.';
        }
        if (site == SearchSite.duckDuckGo || site == SearchSite.youtube) {
          return '${site.label} has no pages of results: it shows more as '
              'you scroll down.';
        }
        final next = resultsPageUrl(url, step: step, number: number);
        if (next == null) {
          return number != null
              ? 'This is page $number already.'
              : 'This is the first page.';
        }
        await view.load(next);
    }
    return null;
  }

  static const _searchFirst =
      'Numbered links work on Google, Bing, DuckDuckGo and YouTube '
      'results: search first.';

  /// Why words that are not a command were not searched for.
  static String _notACommand(VoiceLanguage language) => switch (language.code) {
    'fa' => 'این دستور نبود. برای جستجو بگویید «جستجو کن …».',
    'da' => 'Det var ikke en kommando. Sig “søg efter …” for at søge.',
    'en' => 'That was not a command. To search, say “search …”.',
    _ => 'Not sure what to do with that.',
  };

  void _close() => ref.read(voiceModeProvider.notifier).stop();

  @override
  Widget build(BuildContext context) {
    // Start once the model folder has been checked, and right after the
    // model finishes downloading.
    if (ref.watch(usesWhisperModelsProvider)) {
      ref.listen(whisperModelsProvider, (before, now) {
        final ready = before?.folder == null && now.folder != null;
        final installed =
            now.installed.length > (before?.installed.length ?? 0);
        if ((_phase == _Phase.starting && ready) ||
            (_phase == _Phase.download && installed && !_modelMissing)) {
          _listen();
        }
      });
    }
    // Another language chosen (here or in Settings): listen in it.
    ref.listen(appSettingsProvider.select((s) => s.voiceLanguage), (_, now) {
      if (now == _picked) _picked = null;
      if (_phase == _Phase.listening && _language != _listeningIn) _listen();
    });
    final scheme = Theme.of(context).colorScheme;
    final width = math.min(340.0, MediaQuery.sizeOf(context).width - 32);
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ui.radiusLarge * 1.5),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
          child: _phase == _Phase.download
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(alignment: Alignment.centerRight, child: _closer()),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 10, 4),
                      child: _ModelDownload(onCancel: _close),
                    ),
                  ],
                )
              : _listening(context),
        ),
      ),
    );
  }

  Widget _closer() => IconButton(
    tooltip: 'Turn off voice commands',
    iconSize: 16,
    visualDensity: VisualDensity.compact,
    icon: const Icon(CupertinoIcons.xmark),
    onPressed: _close,
  );

  Widget _listening(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    ref.watch(appSettingsProvider.select((s) => s.voiceLanguage));
    final language = _language;
    final listening = _phase == _Phase.listening;
    final stopped = _phase == _Phase.stopped;
    final paused = _phase == _Phase.idle && !_wanted;
    final (String title, String? detail) = switch (_phase) {
      _ when paused => ('Paused', 'Listens again when you are back.'),
      _Phase.idle || _Phase.starting => ('Getting ready…', null),
      _Phase.listening => ('Listening…', _partial.isEmpty ? null : _partial),
      _Phase.recognizing => ('Recognizing…', null),
      _Phase.stopped => (
        _error?.message ?? SpeechError.failed.message,
        'Tap the microphone to listen again.',
      ),
      _Phase.download => ('', null),
    };
    final heard = _heard;
    final small = theme.textTheme.bodySmall?.copyWith(color: muted);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _MicOrb(
              level: _level,
              busy: _phase == _Phase.recognizing || _phase == _Phase.starting,
              active: listening,
              tooltip: listening
                  ? 'Done speaking'
                  : stopped
                  ? 'Listen again'
                  : null,
              onTap: listening
                  ? () => _input?.finish()
                  : stopped
                  ? () {
                      _quickMisses = 0;
                      _listen();
                    }
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textDirection: voiceTextDirection(detail),
                      style: small,
                    ),
                ],
              ),
            ),
            _closer(),
          ],
        ),
        if (heard != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _done
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.info_circle,
                  size: 15,
                  color: _done ? theme.colorScheme.primary : muted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  voiceTextDirection(heard) == TextDirection.rtl
                      ? '«$heard»'
                      : '“$heard”',
                  key: const ValueKey('voice-heard'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: voiceTextDirection(heard),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (_note case final note?)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 21, top: 2),
              child: Text(
                note,
                textDirection: voiceTextDirection(note),
                style: small,
              ),
            ),
        ] else if (!stopped) ...[
          const SizedBox(height: 6),
          Text(
            _examples(language),
            textDirection: voiceTextDirection(_examples(language)),
            style: small?.copyWith(height: 1.5),
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PopupMenuButton<VoiceLanguage>(
            key: const ValueKey('voice-language'),
            tooltip: 'Language you speak',
            initialValue: language,
            constraints: const BoxConstraints(maxHeight: 380),
            onSelected: _pick,
            itemBuilder: (_) => [
              for (final l in voiceLanguages)
                PopupMenuItem(value: l, child: Text(l.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.globe, size: 14, color: muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      language.nativeName,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(CupertinoIcons.chevron_down, size: 11, color: muted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Right to left for Hebrew, Arabic, Persian and Urdu text.
TextDirection voiceTextDirection(String text) =>
    RegExp('[֐-ࣿ]').hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;

/// What to say, in the language chosen. Commands are understood in these
/// three; in any other language what is said is searched for.
String _examples(VoiceLanguage language) => switch (language.code) {
  'fa' =>
    'بگویید: «جستجو کن ایران»، «برو به یوتیوب»، «لینک دوم رو باز کن»، '
        '«صفحه بعد»، «برگرد»، «اسکرول»، «برو بالا»، «مرورگر رو ببند»',
  'da' =>
    'Sig: “søg efter Iran”, “åbn YouTube”, “åbn det andet link”, '
        '“næste side”, “gå tilbage”, “rul ned”, “rul op”, “luk browseren”',
  'en' =>
    'Say “search Iran”, “open YouTube”, “open the second link”, '
        '“next page”, “go back”, “scroll down”, “scroll up”, '
        '“close browser”',
  _ =>
    'Say what to search for, or the name of a site to open it. '
        '“Scroll”, “scroll up” and “close browser” work too.',
};

/// The microphone: a halo that follows the voice while listening, a ring
/// while recognizing.
class _MicOrb extends StatelessWidget {
  const _MicOrb({
    required this.level,
    required this.busy,
    required this.active,
    this.tooltip,
    this.onTap,
  });

  static const _size = 40.0;

  final double level;
  final bool busy;
  final bool active;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final halo = _size + 6 + 18 * (active ? level : 0.0);
    final lit = active || onTap != null;
    final button = Material(
      color: lit ? scheme.primary : scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Icon(
            CupertinoIcons.mic_fill,
            size: 18,
            color: lit ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    return SizedBox(
      width: _size + 26,
      height: _size + 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: halo,
            height: halo,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: active ? 0.18 : 0.06),
            ),
          ),
          if (busy)
            const SizedBox(
              width: _size + 8,
              height: _size + 8,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          if (tooltip == null)
            button
          else
            Tooltip(message: tooltip, child: button),
        ],
      ),
    );
  }
}

/// Offers the one-time model download (Windows), with progress.
class _ModelDownload extends ConsumerWidget {
  const _ModelDownload({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final model = ref.watch(appSettingsProvider).voiceModel;
    final state = ref.watch(whisperModelsProvider);
    final models = ref.read(whisperModelsProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          CupertinoIcons.waveform,
          size: 40,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 14),
        Text(
          'Download the speech model',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '6browser understands Persian and English voice commands on this '
          'computer, so your voice is never sent anywhere. It needs a '
          'one-time download of ${model.size} (${model.label} model; you '
          'can change it in Settings).',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: muted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        if (state.busy) ...[
          LinearProgressIndicator(value: state.progress),
          const SizedBox(height: 8),
          Text(
            state.verifying
                ? 'Checking the file…'
                : '${(state.received / 1000000).toStringAsFixed(0)} of '
                      '${state.downloading?.size}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          if (!state.verifying)
            Center(
              child: TextButton(
                onPressed: models.cancelDownload,
                child: const Text('Cancel download'),
              ),
            ),
        ] else ...[
          if (state.error case final error?) ...[
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: () => chooseModelFile(ref),
                child: const Text('Choose file…'),
              ),
              FilledButton(
                onPressed: () => models.download(model),
                child: Text('Download (${model.size})'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Installs a model file downloaded elsewhere and makes it the one in use.
Future<void> chooseModelFile(WidgetRef ref) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Whisper model', extensions: ['bin']),
    ],
  );
  if (file == null) return;
  final model = await ref
      .read(whisperModelsProvider.notifier)
      .importFile(file.path);
  if (model != null) {
    await ref.read(databaseProvider).setSetting('voiceModel', model.name);
  }
}
