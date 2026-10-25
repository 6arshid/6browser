import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/appearance_settings.dart';
import '../themes/theme_service.dart';
import 'extension_manifest.dart';
import 'extension_service.dart';

/// What the engine cannot do for extensions, shown before installing.
const extensionLimitsNote =
    'Extensions run in 6browser, but they cannot see or open tabs, so '
    'features that work on "the current tab" may not work.';

/// The manifest and icon inside `.crx`/`.zip` bytes.
(ExtensionManifest, Uint8List?) readPackage(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(crxToZip(bytes));
  String? text(String path) => switch (archive.findFile(path)?.readBytes()) {
    final b? => utf8.decode(b, allowMalformed: true),
    null => null,
  };
  final manifestText = text('manifest.json');
  if (manifestText == null) {
    throw const FormatException('The package has no manifest.json');
  }
  final manifest = ExtensionManifest.parse(
    manifestText,
    readMessages: (locale) => text('_locales/$locale/messages.json'),
  );
  final icon = manifest.icon(48);
  return (
    manifest,
    icon == null ? null : archive.findFile(_relative(icon))?.readBytes(),
  );
}

String _relative(String path) =>
    path.replaceAll(r'\', '/').replaceFirst(RegExp('^/+'), '');

/// Installs Chrome Web Store item [id]: a theme is applied, an extension is
/// installed once the user has confirmed what it can do.
Future<void> runWebStoreInstall(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final messenger = ScaffoldMessenger.of(context);
  _showProgress(messenger, 'Downloading…');
  final Uint8List bytes;
  final ExtensionManifest manifest;
  final Uint8List? icon;
  try {
    bytes = await downloadFromWebStore(id);
    (manifest, icon) = readPackage(bytes);
  } on Object catch (e) {
    _showMessage(messenger, 'Could not download this item: ${_reason(e)}');
    return;
  }
  if (!context.mounted) return;
  if (manifest.isTheme) {
    messenger.hideCurrentSnackBar();
    await runThemeInstall(context, ref, (s) => s.installBytes(bytes, id: id));
    return;
  }
  await _installExtension(
    context,
    ref,
    manifest,
    icon,
    () => ref
        .read(extensionsProvider.notifier)
        .installBytes(bytes, webStoreId: id),
  );
}

/// Installs a `.crx` or `.zip` file chosen by the user.
Future<void> runFileInstall(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final Uint8List bytes;
  final ExtensionManifest manifest;
  final Uint8List? icon;
  try {
    final file = File(path);
    if (await file.length() > maxWebStoreBytes) {
      throw const FormatException('The file is too large');
    }
    bytes = await file.readAsBytes();
    (manifest, icon) = readPackage(bytes);
  } on Object catch (e) {
    _showMessage(messenger, 'Could not open this file: ${_reason(e)}');
    return;
  }
  if (!context.mounted) return;
  if (manifest.isTheme) {
    await runThemeInstall(context, ref, (s) => s.installFromPath(path));
    return;
  }
  await _installExtension(
    context,
    ref,
    manifest,
    icon,
    () => ref.read(extensionsProvider.notifier).installBytes(bytes),
  );
}

Future<void> _installExtension(
  BuildContext context,
  WidgetRef ref,
  ExtensionManifest manifest,
  Uint8List? icon,
  Future<InstalledExtension> Function() install,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(extensionsProvider.notifier);
  if (!controller.supported) {
    _showMessage(
      messenger,
      'Extensions can be installed in 6browser on Windows. This system is '
      'not supported yet.',
    );
    return;
  }
  if (manifest.manifestVersion < 3) {
    _showMessage(
      messenger,
      '"${manifest.name}" is a Manifest V2 extension. Chrome no longer runs '
      'these, and neither does 6browser.',
    );
    return;
  }
  messenger.hideCurrentSnackBar();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => ExtensionInstallDialog(manifest: manifest, icon: icon),
  );
  if (ok != true) return;
  _showProgress(messenger, 'Adding "${manifest.name}"…');
  try {
    final x = await install();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"${x.name}" has been added'),
          action: x.pinned
              ? null
              : SnackBarAction(
                  label: 'Pin to toolbar',
                  onPressed: () => controller.setPinned(x.id, true),
                ),
        ),
      );
  } on Object catch (e) {
    _showMessage(messenger, 'Could not add "${manifest.name}": ${_reason(e)}');
  }
}

String _reason(Object e) => switch (e) {
  NotAnExtensionException() => 'it is a theme, not an extension',
  FormatException(:final message) => message,
  HttpException(:final message) => message,
  SocketException() => 'no connection',
  _ => '$e',
};

void _showProgress(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(text)),
          ],
        ),
        duration: const Duration(minutes: 1),
      ),
    );
}

void _showMessage(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Chrome's "Add `name`?" confirmation, listing what the extension can do.
class ExtensionInstallDialog extends StatelessWidget {
  const ExtensionInstallDialog({super.key, required this.manifest, this.icon});

  final ExtensionManifest manifest;
  final Uint8List? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = manifest.warnings;
    final icon = this.icon;
    return AlertDialog(
      icon: icon == null
          ? const Icon(Icons.extension_outlined, size: 40)
          : Image.memory(
              icon,
              width: 40,
              height: 40,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.extension_outlined, size: 40),
            ),
      title: Text('Add "${manifest.name}"?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (warnings.isNotEmpty) ...[
                const Text('It can:'),
                const SizedBox(height: 6),
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(w)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              Text(
                extensionLimitsNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add extension'),
        ),
      ],
    );
  }
}
