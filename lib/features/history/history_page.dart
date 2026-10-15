import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../tabs/tabs_controller.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _query = '';

  Future<void> _confirmClear(AppDatabase db) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear browsing history?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await db.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear all'),
            onPressed: () => _confirmClear(db),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search history',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<HistoryEntry>>(
              stream: db.watchHistory(query: _query),
              builder: (context, snap) {
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const Center(child: Text('No history'));
                }
                return ListView(
                  children: [
                    for (final h in items)
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(
                          h.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${h.url}\n${_fmt(h.visitedAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Remove from history',
                          icon: const Icon(Icons.close),
                          onPressed: () => db.deleteHistoryEntry(h.id),
                        ),
                        onTap: () {
                          ref.read(tabsProvider.notifier).newTab(url: h.url);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
