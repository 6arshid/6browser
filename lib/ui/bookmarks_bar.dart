import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../features/bookmarks/bookmarks_page.dart';
import '../features/tabs/tabs_controller.dart';
import 'browser_theme.dart';
import 'favicon.dart';
import 'toolbar.dart';

/// Row of bookmarks under the toolbar, oldest first like Chrome's.
class BookmarksBar extends ConsumerWidget {
  const BookmarksBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(bookmarksProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = BrowserColors.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.separator)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final b in items.reversed) _BookmarkChip(bookmark: b),
              ],
            ),
          ),
          IconButton(
            tooltip: 'All bookmarks',
            iconSize: 18,
            color: colors.icon,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => openPage(context, const BookmarksPage()),
          ),
        ],
      ),
    );
  }
}

class _BookmarkChip extends ConsumerWidget {
  const _BookmarkChip({required this.bookmark});

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BrowserColors.of(context);
    final ctl = ref.read(tabsProvider.notifier);
    final title = bookmark.title.trim().isEmpty
        ? Uri.tryParse(bookmark.url)?.host ?? bookmark.url
        : bookmark.title;

    void openInBackground() => ctl.newTab(url: bookmark.url, activate: false);

    Future<void> menu(Offset at) async {
      final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
        items: const [
          PopupMenuItem(value: 'tab', child: Text('Open in new tab')),
          PopupMenuItem(value: 'remove', child: Text('Delete')),
        ],
      );
      switch (choice) {
        case 'tab':
          openInBackground();
        case 'remove':
          ref.read(databaseProvider).removeBookmark(bookmark.id);
      }
    }

    return Listener(
      onPointerDown: (e) {
        if (e.buttons == kMiddleMouseButton) openInBackground();
      },
      child: GestureDetector(
        onSecondaryTapUp: (d) => menu(d.globalPosition),
        child: Tooltip(
          message: '$title\n${bookmark.url}',
          waitDuration: const Duration(milliseconds: 700),
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colors.tabText,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () =>
                ref.read(tabsProvider).active?.view.load(bookmark.url),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Favicon(url: bookmark.url, color: colors.icon),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
