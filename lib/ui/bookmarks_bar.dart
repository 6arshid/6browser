import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../features/bookmarks/bookmark_dialogs.dart';
import '../features/bookmarks/bookmark_drag.dart';
import '../features/bookmarks/bookmark_tree.dart';
import '../features/bookmarks/bookmarks_page.dart';
import '../features/tabs/tabs_controller.dart';
import 'browser_theme.dart';
import 'favicon.dart';
import 'toolbar.dart';

/// Row of bookmarks and folders under the toolbar, in the user's order.
/// Items can be dragged to reorder them or into folders.
class BookmarksBar extends ConsumerWidget {
  const BookmarksBar({super.key});

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'folder', child: Text('Add folder…')),
        PopupMenuItem(value: 'manager', child: Text('Bookmark manager')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'folder':
        await addBookmarkFolder(context, ref);
      case 'manager':
        openPage(context, const BookmarksPage());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(bookmarkTreeProvider);
    final items = tree?.children(null) ?? const <Bookmark>[];
    if (tree == null || items.isEmpty) return const SizedBox.shrink();
    final colors = BrowserColors.of(context);
    final db = ref.read(databaseProvider);
    return Container(
      height: 32,
      color: colors.toolbar,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapUp: (d) => _menu(context, ref, d.globalPosition),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final b in items)
                    BookmarkDropTarget(
                      key: ValueKey(b.id),
                      axis: Axis.horizontal,
                      isFolder: b.isFolder,
                      canAccept: (id, zone) =>
                          canDropBookmark(tree, id, b, zone),
                      onDrop: (id, zone) => dropBookmark(db, tree, id, b, zone),
                      child: BookmarkDraggable(
                        id: b.id,
                        feedback: _ChipFace(item: b, colors: colors),
                        child: b.isFolder
                            ? _FolderChip(tree: tree, folder: b)
                            : _BookmarkChip(bookmark: b),
                      ),
                    ),
                  // Dropping past the last item moves it to the end.
                  BookmarkEndDropTarget(
                    tree: tree,
                    folderId: null,
                    onDrop: (id) => db.moveBookmark(id),
                    child: const SizedBox(width: 48, height: 28),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'All bookmarks',
            iconSize: 15,
            color: colors.icon,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 26),
            icon: const Icon(CupertinoIcons.book),
            onPressed: () => openPage(context, const BookmarksPage()),
          ),
        ],
      ),
    );
  }
}

/// Icon and name of a bar item, also used as the drag feedback.
class _ChipFace extends StatelessWidget {
  const _ChipFace({required this.item, required this.colors});

  final Bookmark item;
  final BrowserColors colors;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    color: colors.toolbar,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.isFolder)
          Icon(CupertinoIcons.folder, size: 16, color: colors.icon)
        else
          Favicon(url: item.url!, color: colors.icon),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            _label(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: colors.tabText),
          ),
        ),
      ],
    ),
  );
}

String _label(Bookmark b) => b.title.trim().isNotEmpty
    ? b.title
    : b.isFolder
    ? 'Folder'
    : Uri.tryParse(b.url!)?.host ?? b.url!;

ButtonStyle _chipStyle(BrowserColors colors) => TextButton.styleFrom(
  foregroundColor: colors.tabText,
  padding: const EdgeInsets.symmetric(horizontal: 8),
  minimumSize: const Size(0, 28),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

class _BookmarkChip extends ConsumerWidget {
  const _BookmarkChip({required this.bookmark});

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BrowserColors.of(context);
    final ctl = ref.read(tabsProvider.notifier);
    final url = bookmark.url!;

    void openInBackground() => ctl.newTab(url: url, activate: false);

    Future<void> menu(Offset at) async {
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
        items: const [
          PopupMenuItem(value: 'tab', child: Text('Open in new tab')),
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'move', child: Text('Move to folder…')),
          PopupMenuItem(value: 'remove', child: Text('Delete')),
        ],
      );
      if (!context.mounted) return;
      switch (choice) {
        case 'tab':
          openInBackground();
        case 'rename':
          await renameBookmark(context, ref, bookmark);
        case 'move':
          await moveBookmarkTo(context, ref, bookmark);
        case 'remove':
          await deleteBookmark(context, ref, bookmark);
      }
    }

    return Listener(
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) openInBackground();
      },
      child: GestureDetector(
        onSecondaryTapUp: (d) => menu(d.globalPosition),
        child: Tooltip(
          message: '${_label(bookmark)}\n$url',
          waitDuration: const Duration(milliseconds: 700),
          child: TextButton(
            style: _chipStyle(colors),
            onPressed: () => ref.read(tabsProvider).active?.view.load(url),
            child: _ChipLabel(item: bookmark, colors: colors),
          ),
        ),
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.item, required this.colors});

  final Bookmark item;
  final BrowserColors colors;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (item.isFolder)
        Icon(CupertinoIcons.folder, size: 16, color: colors.icon)
      else
        Favicon(url: item.url!, color: colors.icon),
      const SizedBox(width: 6),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(
          _label(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5),
        ),
      ),
    ],
  );
}

/// A folder on the bar: opens a menu of its contents, with subfolders as
/// cascading submenus.
class _FolderChip extends ConsumerWidget {
  const _FolderChip({required this.tree, required this.folder});

  final BookmarkTree tree;
  final Bookmark folder;

  List<Widget> _entries(WidgetRef ref, int folderId, Color iconColor) {
    final items = tree.children(folderId);
    if (items.isEmpty) {
      return const [MenuItemButton(onPressed: null, child: Text('(empty)'))];
    }
    return [
      for (final b in items)
        if (b.isFolder)
          SubmenuButton(
            leadingIcon: const Icon(CupertinoIcons.folder, size: 18),
            menuChildren: _entries(ref, b.id, iconColor),
            child: _MenuLabel(_label(b)),
          )
        else
          MenuItemButton(
            leadingIcon: Favicon(url: b.url!, color: iconColor),
            onPressed: () {
              // Ctrl+click opens it in a background tab, as in Chrome.
              if (HardwareKeyboard.instance.isControlPressed) {
                ref
                    .read(tabsProvider.notifier)
                    .newTab(url: b.url!, activate: false);
              } else {
                ref.read(tabsProvider).active?.view.load(b.url!);
              }
            },
            child: _MenuLabel(_label(b)),
          ),
    ];
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'move', child: Text('Move to folder…')),
        PopupMenuItem(value: 'folder', child: Text('Add folder…')),
        PopupMenuItem(value: 'remove', child: Text('Delete')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'rename':
        await renameBookmark(context, ref, folder);
      case 'move':
        await moveBookmarkTo(context, ref, folder);
      case 'folder':
        await addBookmarkFolder(context, ref, parentId: folder.id);
      case 'remove':
        await deleteBookmark(context, ref, folder);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BrowserColors.of(context);
    return MenuAnchor(
      menuChildren: _entries(
        ref,
        folder.id,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      builder: (context, controller, _) => GestureDetector(
        onSecondaryTapUp: (d) => _menu(context, ref, d.globalPosition),
        child: TextButton(
          style: _chipStyle(colors),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: _ChipLabel(item: folder, colors: colors),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 280),
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
