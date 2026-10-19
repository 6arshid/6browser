import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../ui/anchored_popup.dart';
import 'bookmark_tree.dart';

/// Asks for a name. Returns the trimmed text, or null when cancelled.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String action = 'Save',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, initial: initial, action: action),
);

/// Renames a bookmark or folder. An empty bookmark name shows its address;
/// an empty folder name keeps the old one.
Future<void> renameBookmark(
  BuildContext context,
  WidgetRef ref,
  Bookmark item,
) async {
  final name = await showNameDialog(
    context,
    title: item.isFolder ? 'Rename folder' : 'Rename bookmark',
    initial: item.title,
  );
  if (name == null || (name.isEmpty && item.isFolder)) return;
  await ref
      .read(databaseProvider)
      .renameBookmark(item.id, name.isEmpty ? item.url! : name);
}

/// Asks for a folder name and creates the folder at the end of [parentId].
Future<void> addBookmarkFolder(
  BuildContext context,
  WidgetRef ref, {
  int? parentId,
}) async {
  final name = await showNameDialog(
    context,
    title: 'New folder',
    initial: 'New folder',
    action: 'Create',
  );
  if (name == null || name.isEmpty) return;
  await ref.read(databaseProvider).addFolder(name, parentId: parentId);
}

/// Deletes [item]; a folder that still holds bookmarks is confirmed first.
Future<void> deleteBookmark(
  BuildContext context,
  WidgetRef ref,
  Bookmark item,
) async {
  final count = item.isFolder
      ? ref.read(bookmarkTreeProvider)?.bookmarkCount(item.id) ?? 0
      : 0;
  if (count > 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${item.title}"?'),
        content: Text(
          'The folder and the $count bookmark${count == 1 ? '' : 's'} in it '
          'will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await ref.read(databaseProvider).removeBookmark(item.id);
}

/// Lets the user pick a folder for [item] and moves it to the end of it.
Future<void> moveBookmarkTo(
  BuildContext context,
  WidgetRef ref,
  Bookmark item,
) async {
  final tree = ref.read(bookmarkTreeProvider);
  if (tree == null) return;
  final picked = await showDialog<({int? id})>(
    context: context,
    builder: (context) {
      Widget option(int? id, String title, int depth) => ListTile(
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: 16.0 + 20 * depth),
        leading: Icon(id == null ? Icons.bookmarks_outlined : Icons.folder),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: id == item.parentId,
        onTap: () => Navigator.pop(context, (id: id)),
      );
      return AlertDialog(
        title: Text('Move "${item.title}" to'),
        contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: [
              option(null, BookmarkTree.barName, 0),
              for (final f in tree.folders())
                // A folder cannot go inside itself.
                if (!tree.isWithin(f.folder.id, item.id))
                  option(f.folder.id, f.folder.title, f.depth + 1),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
  if (picked == null || picked.id == item.parentId) return;
  await ref.read(databaseProvider).moveBookmark(item.id, folderId: picked.id);
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.action,
  });

  final String title;
  final String initial;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_name.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 400,
      child: TextField(
        key: const ValueKey('bookmark-name'),
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// Chrome's "Bookmark added" box: name, folder, Remove and Done. Opens
/// under [anchor] (the star) on wide screens, in the middle on phones.
Future<void> showBookmarkEditor(
  BuildContext anchor, {
  required int id,
  required bool added,
}) => showAnchoredPopup<void>(
  anchor,
  builder: (_) => _BookmarkEditor(id: id, added: added),
);

class _BookmarkEditor extends ConsumerStatefulWidget {
  const _BookmarkEditor({required this.id, required this.added});

  final int id;
  final bool added;

  @override
  ConsumerState<_BookmarkEditor> createState() => _BookmarkEditorState();
}

class _BookmarkEditorState extends ConsumerState<_BookmarkEditor> {
  static const _bar = -1;
  final _name = TextEditingController();
  int? _folder;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _done(Bookmark item) async {
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    if (name != item.title) {
      await db.renameBookmark(item.id, name.isEmpty ? item.url! : name);
    }
    final folder = _folder == _bar ? null : _folder;
    if (folder != item.parentId) {
      await db.moveBookmark(item.id, folderId: folder);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(bookmarkTreeProvider);
    final item = tree?[widget.id];
    if (tree == null || item == null) return const SizedBox.shrink();
    if (!_loaded) {
      _loaded = true;
      _name.text = item.title;
      _name.selection = TextSelection(
        baseOffset: 0,
        extentOffset: item.title.length,
      );
      _folder = item.parentId ?? _bar;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.added ? 'Bookmark added' : 'Edit bookmark',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('bookmark-name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _done(item),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            key: const ValueKey('bookmark-folder'),
            initialValue: _folder,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Folder',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: _bar,
                child: Text(BookmarkTree.barName),
              ),
              for (final f in tree.folders())
                DropdownMenuItem(
                  value: f.folder.id,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: 16.0 * (f.depth + 1),
                    ),
                    child: Text(
                      f.folder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _folder = v),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  ref.read(databaseProvider).removeBookmark(item.id);
                  Navigator.of(context).pop();
                },
                child: const Text('Remove'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _done(item),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
