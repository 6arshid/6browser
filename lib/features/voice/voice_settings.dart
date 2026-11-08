import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/browser_commands.dart';
import '../../ui/toolbar.dart' show compactBreakpoint;
import '../settings/app_settings.dart';
import 'speech_input.dart';
import 'voice_panel.dart';
import 'voice_tour.dart';
import 'whisper_models.dart';

/// Settings > Voice commands: the language spoken and, on Windows, the
/// speech model.
class VoiceSettings extends ConsumerWidget {
  const VoiceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final whisper = ref.watch(usesWhisperModelsProvider);
    final keyboard = MediaQuery.sizeOf(context).width >= compactBreakpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Click the microphone in the address bar'
          '${keyboard ? ' (or press ${shortcutFor(BrowserCommand.voiceCommand)})' : ''}'
          ' and say what to do: "search Iran", "open YouTube", "new tab", '
          '"go back". Commands are understood in English, Persian and '
          'Danish; in other languages, what you say is searched for.',
          style: TextStyle(color: muted),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(CupertinoIcons.play_circle, size: 18),
            label: const Text('Show the voice tour'),
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              ref.read(voiceTourRequestProvider.notifier).show();
            },
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<VoiceLanguage>(
          key: ValueKey(settings.voiceLanguage),
          initialValue: settings.voiceLanguage,
          menuMaxHeight: 420,
          decoration: const InputDecoration(
            labelText: 'Language you speak',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final language in voiceLanguages)
              DropdownMenuItem(value: language, child: Text(language.label)),
          ],
          onChanged: (v) {
            if (v != null) db.setSetting('voiceLanguage', v.code);
          },
        ),
        if (whisper) ...[
          const SizedBox(height: 20),
          Text('Speech model', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Speech is recognized on this computer with Whisper; your voice '
            'is not sent anywhere.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          for (final model in WhisperModel.values)
            _ModelTile(model: model, selected: model == settings.voiceModel),
          if (ref.watch(whisperModelsProvider).error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => chooseModelFile(ref),
              child: const Text('Choose a model file…'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ModelTile extends ConsumerWidget {
  const _ModelTile({required this.model, required this.selected});

  final WhisperModel model;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(whisperModelsProvider);
    final models = ref.read(whisperModelsProvider.notifier);
    final installed = state.installed.contains(model);
    final downloading = state.downloading == model;
    final scheme = Theme.of(context).colorScheme;
    final status = downloading
        ? state.verifying
              ? 'Checking the file…'
              : 'Downloading… ${((state.progress ?? 0) * 100).round()}%'
        : installed
        ? 'Downloaded'
        : 'Not downloaded';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : null,
      ),
      title: Text('${model.label} · ${model.size}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${model.detail} $status.'),
          if (downloading) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: state.progress),
          ],
        ],
      ),
      isThreeLine: downloading,
      onTap: () =>
          ref.read(databaseProvider).setSetting('voiceModel', model.name),
      trailing: downloading
          ? state.verifying
                ? null
                : TextButton(
                    onPressed: models.cancelDownload,
                    child: const Text('Cancel'),
                  )
          : installed
          ? TextButton(
              onPressed: () => models.delete(model),
              child: const Text('Delete'),
            )
          : TextButton(
              onPressed: state.busy ? null : () => models.download(model),
              child: const Text('Download'),
            ),
    );
  }
}
