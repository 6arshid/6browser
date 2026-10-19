import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../ui/favicon.dart';
import '../tabs/tabs_controller.dart';
import 'bookmark_dialogs.dart';
import 'bookmark_drag.dart';
import 'bookmark_tree.dart';

/// Bookmark manager: browse folders, search, and rearrange by dragging.
class BookmarksPage extends ConsumerStatefulWidget {
  const BookmarksPage({super.key});

  @override
  ConsumerState<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends ConsumerState<BookmarksPage> {
  final _searchController = TextEditingController();
  String _query = '';

  /// The open folder; null for the bookmarks bar.
  int? _folderId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(int? folderId) => setState(() => _folderId = folderId);

  @override
  Widget build(BuildContext context) {
    final bookmarks = ref.watch(bookmarksProvider);
    final tree = ref.watch(bookmarkTreeProvider);
    // The open folder may have been deleted meanwhile.
    final folderId = tree?[_folderId ?? -1] == null ? null : _folderId;
    final query = _query.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final List<Bookmark> items = tree == null
        ? const []
        : searching
        ? [
            for (final b in tree.all)
              if (!b.isFolder &&
                  (b.title.toLowerCase().contains(query) ||
                      b.url!.toLowerCase().contains(query)))
                b,
          ]
        : tree.children(folderId);

    return PopScope(
      // Back leaves the open folder before it leaves the page.
      canPop: folderId == null || searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _open(tree?[folderId!]?.parentId);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bookmarks'),
          actions: [
            IconButton(
              tooltip: 'Add folder',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () =>
                  addBookmarkFolder(context, ref, parentId: folderId),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search bookmarks',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (!searching && tree != null)
              _Breadcrumbs(tree: tree, folderId: folderId, onOpen: _open),
            Expanded(
              child: bookmarks.hasError
                  ? const Center(child: Text('Could not load bookmarks.'))
                  : tree == null
                  ? const Center(child: CircularProgressIndicator())
                  : searching && items.isEmpty
                  ? const Center(child: Text('No matching bookmarks.'))
                  : tree.all.isEmpty
                  ? const Center(
                      child: Text(
                        'No bookmarks yet. Use the star in the address bar.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length + (searching ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == items.length) {
                          return _EndOfFolder(
                            tree: tree,
                            folderId: folderId,
                            empty: items.isEmpty,
                          );
                        }
                        return _BookmarkRow(
                          key: ValueKey(items[index].id),
                          tree: tree,
                          item: items[index],
                          searching: searching,
                          onOpenFolder: _open,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Bookmarks bar › Folder › Subfolder"; each part opens that folder and
/// takes dropped bookmarks.
class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs({
    required this.tree,
    required this.folderId,
    required this.onOpen,
  });

  final BookmarkTree tree;
  final int? folderId;
  final ValueChanged<int?> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget crumb(int? id, String title) => BookmarkEndDropTarget(
      tree: tree,
      folderId: id,
      onDrop: (dragged) => db.moveBookmark(dragged, folderId: id),
      child: TextButton(
        onPressed: id == folderId ? null : () => onOpen(id),
        child: Text(title),
      ),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            crumb(null, BookmarkTree.barName),
            for (final f in tree.path(folderId)) ...[
              Icon(Icons.chevron_right, size: 18, color: muted),
              crumb(f.id, f.title),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookmarkRow extends ConsumerWidget {
  const _BookmarkRow({
    super.key,
    required this.tree,
    required this.item,
    required this.searching,
    required this.onOpenFolder,
  });

  final BookmarkTree tree;
  final Bookmark item;

  /// Search results come from every folder, so they are not reordered.
  final bool searching;
  final ValueChanged<int> onOpenFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final url = item.url;
    final count = item.isFolder ? tree.bookmarkCount(item.id) : 0;
    final where = searching && item.parentId != null
        ? ' · ${tree.path(item.parentId).map((f) => f.title).join(' › ')}'
        : '';

    void openInNewTab() {
      ref.read(tabsProvider.notifier).newTab(url: url);
      Navigator.of(context).pop();
    }

    final tile = ListTile(
      leading: item.isFolder
          ? Icon(Icons.folder, color: muted)
          : Favicon(url: url!, size: 20, color: muted),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.isFolder
            ? '$count bookmark${count == 1 ? '' : 's'}'
            : '$url$where',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => renameBookmark(context, ref, item),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => deleteBookmark(context, ref, item),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (v) {
              switch (v) {
                case 'tab':
                  openInNewTab();
                case 'move':
                  moveBookmarkTo(context, ref, item);
              }
            },
            itemBuilder: (_) => [
              if (!item.isFolder)
                const PopupMenuItem(
                  value: 'tab',
                  child: Text('Open in new tab'),
                ),
              const PopupMenuItem(
                value: 'move',
                child: Text('Move to folder…'),
              ),
            ],
          ),
        ],
      ),
      onTap: () => item.isFolder ? onOpenFolder(item.id) : openInNewTab(),
    );
    if (searching) return tile;
    return BookmarkDropTarget(
      axis: Axis.vertical,
      isFolder: item.isFolder,
      canAccept: (id, zone) => canDropBookmark(tree, id, item, zone),
      onDrop: (id, zone) => dropBookmark(db, tree, id, item, zone),
      child: BookmarkDraggable(
        id: item.id,
        feedback: SizedBox(
          width: 320,
          child: ListTile(
            leading: Icon(
              item.isFolder ? Icons.folder : Icons.bookmark_outline,
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        child: tile,
      ),
    );
  }
}

/// Space after the last item that takes drops "at the end".
class _EndOfFolder extends ConsumerWidget {
  const _EndOfFolder({
    required this.tree,
    required this.folderId,
    required this.empty,
  });

  final BookmarkTree tree;
  final int? folderId;
  final bool empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) => BookmarkEndDropTarget(
    tree: tree,
    folderId: folderId,
    onDrop: (id) =>
        ref.read(databaseProvider).moveBookmark(id, folderId: folderId),
    child: SizedBox(
      height: empty ? 120 : 56,
      child: empty
          ? Center(
              child: Text(
                'This folder is empty.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : null,
    ),
  );
}
