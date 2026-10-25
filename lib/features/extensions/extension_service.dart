import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/providers.dart';
import '../../engine/browser_engine.dart';
import '../tabs/tabs_controller.dart';
import '../themes/theme_service.dart';
import 'crx.dart';
import 'extension_manifest.dart';

/// Where installed extensions are unpacked, one folder per extension, next
/// to the list of installed extensions (extensions.json). Tests override
/// this with a temporary folder.
final extensionsDirProvider = FutureProvider<Directory>((ref) async {
  final data =
      ref.watch(dataDirProvider) ?? await getApplicationSupportDirectory();
  return Directory(p.join(data.path, 'extensions'));
});

/// Installed extensions, in install order.
final extensionsProvider =
    NotifierProvider<ExtensionsController, List<InstalledExtension>>(
      ExtensionsController.new,
    );

/// One installed extension.
class InstalledExtension {
  const InstalledExtension({
    required this.id,
    required this.path,
    required this.manifest,
    this.enabled = true,
    this.pinned = false,
    this.copied = true,
    this.running = false,
    this.error,
  });

  /// The engine's id for it (the Web Store id for store installs).
  final String id;

  /// The unpacked extension's folder.
  final String path;
  final ExtensionManifest manifest;
  final bool enabled;

  /// Shown on the toolbar.
  final bool pinned;

  /// The folder is 6browser's own copy (deleted on removal), not a folder
  /// the user loaded in place.
  final bool copied;

  /// Loaded into the engine in this run.
  final bool running;

  /// Why loading failed, if it did.
  final String? error;

  String get name => manifest.name;

  /// Turned off, but still loaded until 6browser restarts.
  bool get pendingRestart => !enabled && running;

  String? get popupUrl => switch (manifest.popup) {
    final page? when running => 'chrome-extension://$id/$page',
    _ => null,
  };

  String? get optionsUrl => switch (manifest.optionsPage) {
    final page? when running => 'chrome-extension://$id/$page',
    _ => null,
  };

  /// The icon file closest to [size] pixels, if the extension has one.
  File? icon([int size = 32]) => switch (manifest.icon(size)) {
    final rel? => File(p.join(path, rel)),
    null => null,
  };

  InstalledExtension copyWith({
    String? id,
    bool? enabled,
    bool? pinned,
    bool? running,
    String? Function()? error,
  }) => InstalledExtension(
    id: id ?? this.id,
    path: path,
    manifest: manifest,
    enabled: enabled ?? this.enabled,
    pinned: pinned ?? this.pinned,
    copied: copied,
    running: running ?? this.running,
    error: error == null ? this.error : error(),
  );

  Map<String, Object> toJson() => {
    'id': id,
    'path': path,
    'enabled': enabled,
    'pinned': pinned,
    'copied': copied,
  };
}

/// The user tried to install a theme as an extension.
class NotAnExtensionException implements Exception {
  const NotAnExtensionException();
}

/// Installs, loads and removes extensions. The engine forgets extensions
/// between runs, so [loadInstalled] loads them again at every start.
class ExtensionsController extends Notifier<List<InstalledExtension>> {
  /// Serializes changes so two installs never write the list at once.
  Future<void> _queue = Future.value();

  @override
  List<InstalledExtension> build() => const [];

  ExtensionHost? get _host => ref.read(engineProvider).extensions;

  /// False when this engine cannot run extensions.
  bool get supported => _host != null;

  Future<Directory> get _root => ref.read(extensionsDirProvider.future);

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Reads the installed list and loads the enabled extensions into the
  /// engine. Called once, after the engine has started.
  Future<void> loadInstalled() => _locked(() async {
    final host = _host;
    if (host == null) return;
    final file = File(p.join((await _root).path, 'extensions.json'));
    if (!await file.exists()) return;
    final List<Object?> entries;
    try {
      entries =
          (jsonDecode(await file.readAsString()) as Map)['extensions'] as List;
    } on Object {
      return; // a damaged list is ignored, not overwritten until a change
    }
    final out = <InstalledExtension>[];
    for (final e in entries.whereType<Map>()) {
      final path = e['path'] as String? ?? '';
      final ExtensionManifest manifest;
      try {
        manifest = ExtensionManifest.load(Directory(path));
      } on Object {
        continue; // folder deleted or damaged
      }
      out.add(
        InstalledExtension(
          id: e['id'] as String? ?? '',
          path: path,
          manifest: manifest,
          enabled: e['enabled'] as bool? ?? true,
          pinned: e['pinned'] as bool? ?? false,
          copied: e['copied'] as bool? ?? true,
        ),
      );
    }
    state = out;
    await Future.wait([
      for (final x in out)
        if (x.enabled) _load(host, x),
    ]);
  });

  Future<void> _load(ExtensionHost host, InstalledExtension x) async {
    try {
      final id = await host.load(x.path);
      _replace(
        x.id,
        (e) => e.copyWith(id: id, running: true, error: () => null),
      );
    } on Object catch (e) {
      _replace(x.id, (x) => x.copyWith(running: false, error: () => '$e'));
    }
  }

  /// Installs an extension from `.crx` or `.zip` bytes. [webStoreId] is
  /// the id it must keep (from the Web Store). Throws
  /// [NotAnExtensionException] for a theme.
  Future<InstalledExtension> installBytes(
    Uint8List bytes, {
    String? webStoreId,
  }) => _locked(() async {
    final host = _host;
    if (host == null) throw UnsupportedError('Extensions are not supported');
    final archive = ZipDecoder().decodeBytes(crxToZip(bytes));
    final manifestEntry = archive.findFile('manifest.json');
    final manifestBytes = manifestEntry?.readBytes();
    if (manifestBytes == null) {
      throw const FormatException('The package has no manifest.json');
    }
    final json = decodeManifest(utf8.decode(manifestBytes));
    if (json['theme'] is Map) throw const NotAnExtensionException();
    final key = crxPublicKey(bytes, expectedId: webStoreId);
    if (key != null) json['key'] = key;
    final hasKey = json['key'] is String;
    final folder = hasKey
        ? extensionIdForKey(base64.decode(json['key'] as String))
        : 'local-${DateTime.now().millisecondsSinceEpoch}';

    final root = await _root;
    final staging = Directory(p.join(root.path, '$folder.new'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    final dest = Directory(p.join(root.path, folder));
    try {
      var total = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final out = p.normalize(p.join(staging.path, entry.name));
        // Skip entries that would escape the extension folder ("../x").
        if (!p.isWithin(staging.path, out)) continue;
        final content = entry.readBytes();
        if (content == null) continue;
        total += content.length;
        if (total > maxWebStoreBytes) {
          throw const FormatException('The extension is too large');
        }
        await File(out).create(recursive: true);
        await File(out).writeAsBytes(content);
      }
      await File(p.join(staging.path, 'manifest.json'))
          .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
      final old = Directory(p.join(root.path, '$folder.old'));
      if (await old.exists()) await old.delete(recursive: true);
      if (await dest.exists()) await dest.rename(old.path);
      await staging.rename(dest.path);
      if (await old.exists()) await old.delete(recursive: true);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
    return _add(host, dest.path, copied: true);
  });

  /// Loads the unpacked extension in [dir] in place, like Chrome's "Load
  /// unpacked". The folder must stay where it is.
  Future<InstalledExtension> loadUnpacked(String dir) => _locked(() async {
    final host = _host;
    if (host == null) throw UnsupportedError('Extensions are not supported');
    if (ExtensionManifest.load(Directory(dir)).isTheme) {
      throw const NotAnExtensionException();
    }
    return _add(host, dir, copied: false);
  });

  Future<InstalledExtension> _add(
    ExtensionHost host,
    String path, {
    required bool copied,
  }) async {
    final manifest = ExtensionManifest.load(Directory(path));
    final id = await host.load(path);
    final previous = state.where((e) => e.id == id).firstOrNull;
    final x = InstalledExtension(
      id: id,
      path: path,
      manifest: manifest,
      pinned: previous?.pinned ?? false,
      copied: copied,
      running: true,
    );
    // An update keeps its place in the list.
    state = previous == null
        ? [...state, x]
        : [for (final e in state) e.id == id ? x : e];
    if (previous != null && previous.copied && previous.path != path) {
      await _deleteFolder(previous.path);
    }
    await _save();
    return x;
  }

  /// Removes the extension and the data it stored.
  Future<void> remove(String id) => _locked(() async {
    final x = state.where((e) => e.id == id).firstOrNull;
    if (x == null) return;
    if (x.running) await _host?.unload(id);
    state = [
      for (final e in state)
        if (e.id != id) e,
    ];
    await _save();
    if (x.copied) await _deleteFolder(x.path);
  });

  /// Turns the extension on at once, or off from the next start: the engine
  /// can only unload an extension by deleting its data.
  Future<void> setEnabled(String id, bool enabled) => _locked(() async {
    final x = state.where((e) => e.id == id).firstOrNull;
    final host = _host;
    if (x == null || host == null) return;
    _replace(id, (e) => e.copyWith(enabled: enabled));
    await _save();
    if (enabled && !x.running) {
      await _load(host, state.firstWhere((e) => e.id == id));
    }
  });

  Future<void> setPinned(String id, bool pinned) => _locked(() async {
    _replace(id, (e) => e.copyWith(pinned: pinned));
    await _save();
  });

  void _replace(String id, InstalledExtension Function(InstalledExtension) f) {
    state = [for (final e in state) e.id == id ? f(e) : e];
  }

  Future<void> _deleteFolder(String path) async {
    final root = (await _root).path;
    // Only 6browser's own copies are ever deleted.
    if (!p.isWithin(root, path)) return;
    final dir = Directory(path);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Still in use; the folder is unused from now on.
    }
  }

  Future<void> _save() async {
    final root = await _root;
    await root.create(recursive: true);
    final file = File(p.join(root.path, 'extensions.json'));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'extensions': [for (final e in state) e.toJson()],
      }),
    );
    await temp.rename(file.path);
  }
}
