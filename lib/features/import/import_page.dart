import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/providers.dart';
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
    final added = await _service.importBookmarks(result.bookmarks);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $added new bookmark(s).'),
        ),
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
      body: _profiles.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No Chrome, Edge, Brave or Firefox profiles were found on '
                  'this machine.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Source profile', style: title),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<BrowserProfile>(
                        initialValue: _selected,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final pr in _profiles)
                            DropdownMenuItem(value: pr, child: Text(pr.label)),
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
                if (_busy) const Center(child: CircularProgressIndicator()),
                if (_result != null) ..._results(_result!, title),
              ],
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
          leading: Icon(
            e.enabled ? Icons.extension : Icons.extension_off,
          ),
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
