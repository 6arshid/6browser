import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/providers.dart';
import '../settings/app_settings.dart';
import 'chrome_theme.dart';

/// Themes larger than this are refused (real themes are a few MB).
const _maxThemeBytes = 64 * 1024 * 1024;

/// Chrome version reported to the Web Store when downloading a theme.
const _prodVersion = '149.0.0.0';

/// Where installed themes are unpacked, one folder per theme.
/// Tests override this with a temporary folder.
final themesDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'themes'));
});

final themeServiceProvider = Provider<ThemeService>((ref) => ThemeService(ref));

/// The installed Chrome theme in use, or null for the built-in look.
final chromeThemeProvider = FutureProvider<ChromeTheme?>((ref) async {
  final id = ref.watch(appSettingsProvider.select((s) => s.chromeTheme));
  if (id.isEmpty) return null;
  final root = await ref.watch(themesDirProvider.future);
  try {
    return ChromeTheme.load(Directory(p.join(root.path, id)));
  } on Object {
    // A theme folder that was deleted or damaged falls back to the default.
    return null;
  }
});

/// Extension ID in a Chrome Web Store detail URL, or null.
String? webStoreItemId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final isStore =
      uri.host == 'chromewebstore.google.com' ||
      (uri.host == 'chrome.google.com' &&
          uri.pathSegments.firstOrNull == 'webstore');
  if (!isStore || !uri.pathSegments.contains('detail')) return null;
  return uri.pathSegments.reversed
      .where((s) => RegExp(r'^[a-p]{32}$').hasMatch(s))
      .firstOrNull;
}

/// The ZIP payload of a CRX2/CRX3 package. Plain ZIP data is returned as is.
Uint8List crxToZip(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) return bytes;
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'Cr24') {
    throw const FormatException('Not a .crx or .zip file');
  }
  final data = ByteData.sublistView(bytes);
  final version = data.getUint32(4, Endian.little);
  final int start;
  switch (version) {
    case 2:
      if (bytes.length < 16) throw const FormatException('Damaged .crx file');
      start =
          16 +
          data.getUint32(8, Endian.little) +
          data.getUint32(12, Endian.little);
    case 3:
      start = 12 + data.getUint32(8, Endian.little);
    default:
      throw FormatException('Unsupported .crx version $version');
  }
  if (start >= bytes.length) throw const FormatException('Damaged .crx file');
  return Uint8List.sublistView(bytes, start);
}

/// Installs, applies and removes Chrome themes.
class ThemeService {
  ThemeService(this._ref);

  final Ref _ref;

  Future<Directory> get _root => _ref.read(themesDirProvider.future);

  /// Downloads a theme from the Chrome Web Store and applies it.
  Future<ChromeTheme> installFromWebStore(String id) async {
    final url = Uri.https('clients2.google.com', '/service/update2/crx', {
      'response': 'redirect',
      'prodversion': _prodVersion,
      'acceptformat': 'crx2,crx3',
      'x': 'id=$id&installsource=ondemand&uc',
    });
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(url)).close();
      if (res.statusCode != 200) {
        throw HttpException('Download failed (HTTP ${res.statusCode})');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
        if (builder.length > _maxThemeBytes) {
          throw const FormatException('The download is too large');
        }
      }
      return await installBytes(builder.takeBytes(), id: id);
    } finally {
      client.close(force: true);
    }
  }

  /// Installs a `.crx` or `.zip` file, or an unpacked theme folder.
  Future<ChromeTheme> installFromPath(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      final archive = Archive();
      await for (final e in Directory(path).list(recursive: true)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: path).replaceAll(r'\', '/');
        archive.add(ArchiveFile.bytes(rel, await e.readAsBytes()));
      }
      return _install(archive, _idFor(path));
    }
    final file = File(path);
    if (await file.length() > _maxThemeBytes) {
      throw const FormatException('The file is too large');
    }
    return installBytes(await file.readAsBytes(), id: _idFor(path));
  }

  /// Installs a theme from `.crx`/`.zip` bytes under [id] and applies it.
  Future<ChromeTheme> installBytes(Uint8List bytes, {required String id}) =>
      _install(ZipDecoder().decodeBytes(crxToZip(bytes)), id);

  Future<ChromeTheme> _install(Archive archive, String id) async {
    final root = await _root;
    final staging = Directory(p.join(root.path, '$id.new'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      var total = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final out = p.normalize(p.join(staging.path, entry.name));
        // Skip entries that would escape the theme folder ("../x").
        if (!p.isWithin(staging.path, out)) continue;
        final content = entry.readBytes();
        if (content == null) continue;
        total += content.length;
        if (total > _maxThemeBytes) {
          throw const FormatException('The theme is too large');
        }
        await File(out).create(recursive: true);
        await File(out).writeAsBytes(content);
      }
      final theme = ChromeTheme.load(staging);
      final dest = Directory(p.join(root.path, id));
      if (await dest.exists()) await dest.delete(recursive: true);
      await staging.rename(dest.path);
      await apply(id);
      return theme;
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  /// Uses the installed theme [id] (empty for none).
  Future<void> apply(String id) async {
    final db = _ref.read(databaseProvider);
    await db.setSetting('chromeTheme', id);
    // A Chrome theme replaces the color palette, as in Chrome.
    if (id.isNotEmpty) await db.setSetting('colorSeed', '');
  }

  /// Back to the built-in look and deletes the installed theme's files.
  Future<void> reset() async {
    final id = _ref.read(appSettingsProvider).chromeTheme;
    await apply('');
    if (id.isEmpty) return;
    final dir = Directory(p.join((await _root).path, id));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// A folder name for a theme loaded from disk.
  String _idFor(String path) {
    final base = p
        .basenameWithoutExtension(path)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    return 'local-${base.isEmpty ? 'theme' : base}';
  }
}
