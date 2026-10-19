import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/providers.dart';
import '../passwords/password_store.dart';
import 'bookmark_file_parser.dart';
import 'browser_detector.dart';
import 'import_models.dart';
import 'import_service.dart';

/// Import bookmarks, passwords and the extension list from other browsers.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.detector});

  /// Overridable for tests (point it at fixture directories).
  final BrowserDetector? detector;

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  late final List<BrowserProfile> _profiles;
  BrowserProfile? _selected;
  ProfileImport? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _profiles = (widget.detector ?? BrowserDetector()).detect();
    if (_profiles.isNotEmpty) _selected = _profiles.first;
  }

  ImportService get _service => ImportService(ref.read(databaseProvider));

  Future<void> _scan() async {
    final profile = _selected;
    if (profile == null) return;
    setState(() => _busy = true);
    // Yield so the spinner paints before the (synchronous) file reads.
    await Future<void>.delayed(Duration.zero);
    final result = _service.read(profile);
    if (mounted) {
      setState(() {
        _result = result;
        _busy = false;
      });
    }
  }

  Future<void> _importBookmarks() async {
    final result = _result;
    if (result == null) return;
    final r = await _service.importBookmarks(result.bookmarks);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${r.added} new bookmark(s).${_moved(r.moved)}',
          ),
        ),
      );
    }
  }

  static String _moved(int n) =>
      n == 0 ? '' : ' Moved $n existing bookmark(s) into their folders.';

  /// Mobile browsers can't be read directly (each app's data is sandboxed),
  /// so the user exports a bookmarks file there and picks it here.
  Future<void> _importBookmarksFile() async {
    // Android/iOS pickers can't filter by extension reliably; exported files
    // often come through as text/plain or application/octet-stream.
    final file = await openFile(
      acceptedTypeGroups: _isMobile
          ? const []
          : const [
              XTypeGroup(
                label: 'Bookmarks',
                extensions: ['html', 'htm', 'json'],
              ),
              XTypeGroup(label: 'All files'),
            ],
    );
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      final marks = BookmarkFileParser.parse(await file.readAsString());
      final r = await _service.importBookmarks(marks);
      message = marks.isEmpty
          ? 'No bookmarks found in ${file.name}.'
          : 'Imported ${r.added} new bookmark(s) of ${marks.length} in '
                '${file.name}.${_moved(r.moved)}';
    } on FormatException {
      message = '${file.name} is not a bookmarks HTML or JSON export.';
    } catch (e) {
      message = 'Could not read ${file.name}: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Saves the decrypted passwords into this profile's password manager.
  Future<void> _savePasswords() async {
    final logins = _result?.logins ?? const [];
    if (logins.isEmpty) return;
    final saved = await ref.read(passwordStoreProvider).import(logins);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved password(s) in 6browser.')),
      );
    }
  }

  Future<void> _exportPasswords() async {
    final logins = _result?.logins ?? const [];
    if (logins.isEmpty) return;
    final dir =
        await getDownloadsDirectory() ?? await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, '6browser-passwords.csv'));
    final buf = StringBuffer('name,url,username,password\r\n');
    for (final l in logins) {
      buf.writeln(
        '${_csv(Uri.tryParse(l.url)?.host ?? l.url)},${_csv(l.url)},'
        '${_csv(l.username)},${_csv(l.password)}',
      );
    }
    await file.writeAsString(buf.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${logins.length} to ${file.path}')),
      );
    }
  }

  static String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Import from another browser')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_profiles.isNotEmpty) ...[
            Text('Source profile', style: title),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<BrowserProfile>(
                    initialValue: _selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final pr in _profiles)
                        DropdownMenuItem(
                          value: pr,
                          child: Text(
                            pr.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy ? null : _scan,
                  child: const Text('Scan'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ] else if (!_isMobile) ...[
            const Text(
              'No Chrome, Edge, Brave or Firefox profiles were found on '
              'this machine.',
            ),
            const SizedBox(height: 24),
          ],
          _fileImportCard(title),
          const SizedBox(height: 24),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_result != null) ..._results(_result!, title),
        ],
      ),
    );
  }

  Widget _fileImportCard(TextStyle? title) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bookmarks file', style: title),
            const SizedBox(height: 8),
            if (_isMobile)
              Text(
                "Android and iOS don't let apps read other browsers' data, "
                'so export your bookmarks first and pick the file here:',
                style: TextStyle(color: muted),
              )
            else
              Text(
                'Import a bookmarks.html or Chromium Bookmarks file exported '
                'from any browser.',
                style: TextStyle(color: muted),
              ),
            if (_isMobile) ...[
              const SizedBox(height: 8),
              for (final step in const [
                'Chrome / Edge / Brave (desktop): Bookmarks manager → ⋮ → '
                    'Export bookmarks.',
                'Firefox (desktop): Bookmarks → Manage bookmarks → '
                    'Import and Backup → Export to HTML.',
                'Phone-only bookmarks: turn on sync in that browser, then '
                    'export from its desktop version.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $step', style: TextStyle(color: muted)),
                ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _importBookmarksFile,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Choose bookmarks file'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _results(ProfileImport r, TextStyle? title) {
    return [
      // Bookmarks
      Text('Bookmarks', style: title),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: Text('${r.bookmarks.length} found')),
          FilledButton.tonal(
            onPressed: r.bookmarks.isEmpty ? null : _importBookmarks,
            child: Text('Import ${r.bookmarks.length}'),
          ),
        ],
      ),
      const SizedBox(height: 24),

      // Passwords
      Text('Passwords', style: title),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: Text('${r.logins.length} decrypted')),
          if (ref.read(passwordStoreProvider).isAvailable) ...[
            FilledButton(
              onPressed: r.logins.isEmpty ? null : _savePasswords,
              child: Text('Save ${r.logins.length} in 6browser'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.tonal(
            onPressed: r.logins.isEmpty ? null : _exportPasswords,
            child: const Text('Export CSV'),
          ),
        ],
      ),
      const SizedBox(height: 24),

      // Extensions
      Text('Extensions (${r.extensions.length})', style: title),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Installing extensions is not supported by the current engine. '
          'This list is for reference only.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
      for (final e in r.extensions)
        ListTile(
          dense: true,
          leading: Icon(e.enabled ? Icons.extension : Icons.extension_off),
          title: Text(e.name),
          subtitle: Text(
            [if (e.version != null) 'v${e.version}', e.id].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

      // Issues
      if (r.issues.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Notes', style: title),
        for (final i in r.issues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('• [${i.category}] ${i.message}'),
          ),
      ],
    ];
  }
}
