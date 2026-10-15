import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';

/// Human readable size, e.g. 1.5 MB.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}

/// Progress 0..1, or null when the total size is unknown.
double? downloadProgress(Download d) =>
    d.totalBytes > 0 ? (d.receivedBytes / d.totalBytes).clamp(0.0, 1.0) : null;

Future<void> _reveal(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', ['/select,', path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else {
    await Process.run('xdg-open', [File(path).parent.path]);
  }
}

Future<void> _open(String path) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}

class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear finished'),
            onPressed: db.clearFinishedDownloads,
          ),
        ],
      ),
      body: StreamBuilder<List<Download>>(
        stream: db.watchDownloads(),
        builder: (context, snap) {
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No downloads'));
          }
          return ListView(
            children: [
              for (final d in items)
                ListTile(
                  leading: Icon(switch (d.state) {
                    'complete' => Icons.check_circle_outline,
                    'canceled' => Icons.cancel_outlined,
                    _ => Icons.downloading,
                  }),
                  title: Text(
                    d.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: d.state == 'inProgress'
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(value: downloadProgress(d)),
                            Text(
                              d.totalBytes > 0
                                  ? '${formatBytes(d.receivedBytes)} of '
                                        '${formatBytes(d.totalBytes)}'
                                  : formatBytes(d.receivedBytes),
                            ),
                          ],
                        )
                      : Text(
                          d.state == 'complete'
                              ? '${formatBytes(d.receivedBytes)} · ${d.path}'
                              : 'Canceled',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (d.state == 'complete') ...[
                        IconButton(
                          tooltip: 'Open file',
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _open(d.path),
                        ),
                        IconButton(
                          tooltip: 'Show in folder',
                          icon: const Icon(Icons.folder_open),
                          onPressed: () => _reveal(d.path),
                        ),
                      ],
                      if (d.state != 'inProgress')
                        IconButton(
                          tooltip: 'Remove from list',
                          icon: const Icon(Icons.close),
                          onPressed: () => db.removeDownload(d.id),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
