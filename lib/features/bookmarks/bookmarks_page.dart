import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../tabs/tabs_controller.dart';

class BookmarksPage extends ConsumerWidget {
  const BookmarksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: StreamBuilder<List<Bookmark>>(
        stream: db.watchBookmarks(),
        builder: (context, snap) {
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Text('No bookmarks yet. Use the star in the address bar.'),
            );
          }
          return ListView(
            children: [
              for (final b in items)
                ListTile(
                  leading: const Icon(Icons.star),
                  title: Text(
                    b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    b.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => db.removeBookmark(b.id),
                  ),
                  onTap: () {
                    ref.read(tabsProvider.notifier).newTab(url: b.url);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
