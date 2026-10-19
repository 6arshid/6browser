import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';

extension BookmarkKind on Bookmark {
  bool get isFolder => url == null;
}

/// The bookmarks as folders and items. Folder id null is the bookmarks bar.
class BookmarkTree {
  BookmarkTree(List<Bookmark> all) : _byId = {for (final b in all) b.id: b} {
    for (final b in all) {
      (_children[b.parentId] ??= []).add(b);
    }
    for (final list in _children.values) {
      list.sort(
        (a, b) => a.position != b.position
            ? a.position.compareTo(b.position)
            : a.id.compareTo(b.id),
      );
    }
  }

  static const barName = 'Bookmarks bar';

  final Map<int, Bookmark> _byId;
  final Map<int?, List<Bookmark>> _children = {};

  Bookmark? operator [](int id) => _byId[id];

  Iterable<Bookmark> get all => _byId.values;

  /// Items of [folderId] in display order.
  List<Bookmark> children(int? folderId) => _children[folderId] ?? const [];

  /// The folders from the bar down to [folderId], not counting the bar.
  List<Bookmark> path(int? folderId) {
    final out = <Bookmark>[];
    for (var f = _byId[folderId]; f != null; f = _byId[f.parentId]) {
      out.insert(0, f);
      if (out.length > _byId.length) break;
    }
    return out;
  }

  String folderName(int? folderId) => _byId[folderId]?.title ?? barName;

  /// Whether [id] is [folderId] or somewhere inside it.
  bool isWithin(int id, int folderId) =>
      path(_byId[id]?.isFolder == true ? id : _byId[id]?.parentId)
          .any((f) => f.id == folderId);

  /// Number of bookmarks (not folders) inside [folderId], at any depth.
  int bookmarkCount(int folderId) {
    var n = 0;
    for (final b in children(folderId)) {
      n += b.isFolder ? bookmarkCount(b.id) : 1;
    }
    return n;
  }

  /// Every folder, depth first in display order, for folder pickers.
  List<({Bookmark folder, int depth})> folders() {
    final out = <({Bookmark folder, int depth})>[];
    void walk(int? parent, int depth) {
      for (final b in children(parent)) {
        if (!b.isFolder) continue;
        out.add((folder: b, depth: depth));
        walk(b.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }
}

/// All bookmarks as a tree; null until the database has answered.
final bookmarkTreeProvider = Provider<BookmarkTree?>(
  (ref) => switch (ref.watch(bookmarksProvider).value) {
    final all? => BookmarkTree(all),
    null => null,
  },
);
