import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whisper_voice/whisper_voice.dart';

import '../../data/providers.dart';
import '../../engine/browser_engine.dart';
import '../../ui/browser_commands.dart';
import '../../ui/browser_theme.dart';
import '../settings/app_settings.dart';
import '../tabs/tabs_controller.dart';
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

/// Listens for a voice command and carries it out in [view]'s tab.
Future<void> runVoiceCommand(
  BuildContext context,
  WidgetRef ref,
  BrowserView view,
) async {
  final commands = BrowserCommands.maybeOf(context);
  final action = await showDialog<VoiceAction>(
    context: context,
    builder: (_) => const VoicePanel(),
  );
  switch (action) {
    case null:
      return;
    case VoiceNavigate(:final url, newTab: true):
      ref
          .read(tabsProvider.notifier)
          .newTab(url: url, incognito: view.incognito);
    case VoiceNavigate(:final url):
      await view.load(url);
    case VoiceRunCommand(:final command):
      commands?.run(command);
  }
}

enum _Phase { starting, download, listening, recognizing, failed, unclear }

/// Listens and shows what is happening; closes with the [VoiceAction] that
/// was asked for.
class VoicePanel extends ConsumerStatefulWidget {
  const VoicePanel({super.key});

  @override
  ConsumerState<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends ConsumerState<VoicePanel> {
  late final SpeechInput? _input = ref.read(speechInputProvider);
  StreamSubscription<SpeechEvent>? _session;
  _Phase _phase = _Phase.starting;
  double _level = 0;
  String _heard = '';
  SpeechError? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _session?.cancel();
    _input?.cancel();
    super.dispose();
  }

  bool get _modelMissing {
    if (!ref.read(usesWhisperModelsProvider)) return false;
    final model = ref.read(appSettingsProvider).voiceModel;
    return ref.read(whisperModelsProvider).fileOf(model) == null;
  }

  void _listen([VoiceLanguage? language]) {
    final input = _input;
    if (input == null) return;
    _session?.cancel();
    _session = null;
    if (ref.read(usesWhisperModelsProvider) &&
        ref.read(whisperModelsProvider).folder == null) {
      _set(_Phase.starting); // waiting for the model folder to be checked
      return;
    }
    if (_modelMissing) {
      _set(_Phase.download);
      return;
    }
    _set(_Phase.listening);
    _session = input
        .listen(language ?? ref.read(appSettingsProvider).voiceLanguage)
        .listen(_onEvent);
  }

  void _set(_Phase phase, {SpeechError? error, String heard = ''}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _error = error;
      _heard = heard;
      _level = 0;
    });
  }

  void _onEvent(SpeechEvent event) {
    if (!mounted) return;
    switch (event) {
      case SpeechLevel(:final level):
        setState(() => _level = level);
      case SpeechPartial(:final text):
        setState(() => _heard = text);
      case SpeechRecognizing():
        _set(_Phase.recognizing, heard: _heard);
      case SpeechResult(:final text):
        final action = parseVoiceCommand(
          text,
          searchTemplate: ref.read(appSettingsProvider).searchTemplate,
        );
        if (action == null) {
          _set(_Phase.unclear, heard: text);
        } else {
          Navigator.of(context).pop(action);
        }
      case SpeechFailed(:final error):
        _set(
          error == SpeechError.modelMissing ? _Phase.download : _Phase.failed,
          error: error,
        );
    }
  }

  void _setLanguage(VoiceLanguage language) {
    ref.read(databaseProvider).setSetting('voiceLanguage', language.code);
    if (_phase != _Phase.download) _listen(language);
  }

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
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ui.radiusLarge * 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 8, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(CupertinoIcons.xmark, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: _phase == _Phase.download
                    ? _ModelDownload(
                        onCancel: () => Navigator.of(context).pop(),
                      )
                    : _listening(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listening(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final listening = _phase == _Phase.listening;
    final retry = _phase == _Phase.failed || _phase == _Phase.unclear;
    final language = ref.watch(appSettingsProvider).voiceLanguage;
    final title = switch (_phase) {
      _Phase.starting => 'Getting ready…',
      _Phase.listening => 'Listening…',
      _Phase.recognizing => 'Recognizing…',
      _Phase.unclear => 'Not sure what to do with that.',
      _Phase.failed => _error?.message ?? SpeechError.failed.message,
      _Phase.download => '',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MicOrb(
          level: _level,
          busy: _phase == _Phase.recognizing || _phase == _Phase.starting,
          active: listening,
          tooltip: listening
              ? 'Done speaking'
              : retry
              ? 'Try again'
              : null,
          onTap: listening
              ? () => _input?.finish()
              : retry
              ? () => _listen()
              : null,
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (_heard.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '“$_heard”',
            key: const ValueKey('voice-heard'),
            textAlign: TextAlign.center,
            textDirection: _directionOf(_heard),
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          retry ? 'Tap the microphone to try again.' : _examples(language),
          textAlign: TextAlign.center,
          textDirection: _directionOf(_examples(language)),
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.6),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: PopupMenuButton<VoiceLanguage>(
                  key: const ValueKey('voice-language'),
                  tooltip: 'Language you speak',
                  initialValue: language,
                  constraints: const BoxConstraints(maxHeight: 380),
                  onSelected: _setLanguage,
                  itemBuilder: (_) => [
                    for (final l in voiceLanguages)
                      PopupMenuItem(value: l, child: Text(l.label)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.globe, size: 16, color: muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            language.nativeName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 12,
                          color: muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (listening)
              TextButton(
                onPressed: () => _input?.finish(),
                child: const Text('Done'),
              ),
          ],
        ),
      ],
    );
  }
}

// Hebrew, Arabic, Persian, Urdu.
TextDirection _directionOf(String text) =>
    RegExp('[֐-ࣿ]').hasMatch(text) ? TextDirection.rtl : TextDirection.ltr;

/// What to say, in the language chosen. Commands are understood in these
/// three; in any other language what is said is searched for.
String _examples(VoiceLanguage language) => switch (language.code) {
  'fa' => 'بگویید: «جستجو کن ایران»، «برو به یوتیوب»، «تب جدید»',
  'da' => 'Sig: “søg efter Iran”, “åbn YouTube”, “ny fane”',
  'en' => 'Say “search Iran”, “open YouTube”, “new tab”',
  _ => 'Say what to search for, or the name of a site to open it.',
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

  final double level;
  final bool busy;
  final bool active;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final halo = 80 + 44 * (active ? level : 0.0);
    final button = Material(
      color: active || onTap != null
          ? scheme.primary
          : scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(
            CupertinoIcons.mic_fill,
            size: 30,
            color: active || onTap != null
                ? scheme.onPrimary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: halo,
            height: halo,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: active ? 0.16 : 0.06),
            ),
          ),
          if (busy)
            const SizedBox(
              width: 86,
              height: 86,
              child: CircularProgressIndicator(strokeWidth: 3),
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
