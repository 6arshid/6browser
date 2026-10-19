import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/database.dart';
import 'bookmark_tree.dart';

/// Drag payload: the bookmark or folder being moved.
class BookmarkDrag {
  const BookmarkDrag(this.id);

  final int id;
}

/// Where a dragged bookmark lands relative to the item under the pointer.
enum DropZone { before, inside, after }

/// Whether bookmark [dragged] may be dropped at [zone] of [target]: never
/// onto itself, and a folder never into itself or one of its subfolders.
bool canDropBookmark(
  BookmarkTree tree,
  int dragged,
  Bookmark target,
  DropZone zone,
) {
  if (dragged == target.id) return false;
  final folder = zone == DropZone.inside ? target.id : target.parentId;
  return folder == null || !tree.isWithin(folder, dragged);
}

/// Moves [dragged] to [zone] of [target].
Future<void> dropBookmark(
  AppDatabase db,
  BookmarkTree tree,
  int dragged,
  Bookmark target,
  DropZone zone,
) {
  switch (zone) {
    case DropZone.inside:
      return db.moveBookmark(dragged, folderId: target.id);
    case DropZone.before:
      return db.moveBookmark(
        dragged,
        folderId: target.parentId,
        beforeId: target.id,
      );
    case DropZone.after:
      final siblings = [
        for (final b in tree.children(target.parentId))
          if (b.id != dragged) b,
      ];
      final i = siblings.indexWhere((b) => b.id == target.id);
      return db.moveBookmark(
        dragged,
        folderId: target.parentId,
        beforeId: i + 1 < siblings.length ? siblings[i + 1].id : null,
      );
  }
}

/// Makes [child] draggable as bookmark [id]: right away with a mouse, after
/// a long press on touch screens so that lists still scroll.
class BookmarkDraggable extends StatelessWidget {
  const BookmarkDraggable({
    super.key,
    required this.id,
    required this.feedback,
    required this.child,
  });

  final int id;

  /// What follows the pointer while dragging.
  final Widget feedback;
  final Widget child;

  static bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final ghost = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Opacity(opacity: 0.9, child: feedback),
    );
    final dimmed = Opacity(opacity: 0.4, child: child);
    return _touch
        ? LongPressDraggable<BookmarkDrag>(
            data: BookmarkDrag(id),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: ghost,
            childWhenDragging: dimmed,
            child: child,
          )
        : Draggable<BookmarkDrag>(
            data: BookmarkDrag(id),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: ghost,
            childWhenDragging: dimmed,
            child: child,
          );
  }
}

/// Accepts dragged bookmarks before or after [child] along [axis], or into
/// it when it is a folder (its middle half), and marks where they would go.
class BookmarkDropTarget extends StatefulWidget {
  const BookmarkDropTarget({
    super.key,
    required this.axis,
    required this.isFolder,
    required this.canAccept,
    required this.onDrop,
    required this.child,
  });

  final Axis axis;
  final bool isFolder;
  final bool Function(int id, DropZone zone) canAccept;
  final void Function(int id, DropZone zone) onDrop;
  final Widget child;

  @override
  State<BookmarkDropTarget> createState() => _BookmarkDropTargetState();
}

class _BookmarkDropTargetState extends State<BookmarkDropTarget> {
  DropZone? _zone;

  /// [global] is the pointer: drags use [pointerDragAnchorStrategy].
  DropZone _zoneAt(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(global);
    var f = widget.axis == Axis.horizontal
        ? local.dx / box.size.width
        : local.dy / box.size.height;
    if (widget.axis == Axis.horizontal &&
        Directionality.of(context) == TextDirection.rtl) {
      f = 1 - f;
    }
    if (widget.isFolder) {
      return f < 0.25
          ? DropZone.before
          : f > 0.75
          ? DropZone.after
          : DropZone.inside;
    }
    return f < 0.5 ? DropZone.before : DropZone.after;
  }

  void _show(DropZone? zone) {
    if (zone != _zone) setState(() => _zone = zone);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final horizontal = widget.axis == Axis.horizontal;
    return DragTarget<BookmarkDrag>(
      onMove: (d) {
        final zone = _zoneAt(d.offset);
        _show(widget.canAccept(d.data.id, zone) ? zone : null);
      },
      onLeave: (_) => _show(null),
      onAcceptWithDetails: (d) {
        final zone = _zoneAt(d.offset);
        _show(null);
        if (widget.canAccept(d.data.id, zone)) widget.onDrop(d.data.id, zone);
      },
      builder: (context, _, _) => Stack(
        children: [
          widget.child,
          if (_zone == DropZone.inside)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(color: color, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            )
          else if (_zone != null)
            PositionedDirectional(
              start: horizontal ? (_zone == DropZone.before ? 0 : null) : 0,
              end: horizontal ? (_zone == DropZone.after ? 0 : null) : 0,
              top: horizontal ? 2 : (_zone == DropZone.before ? 0 : null),
              bottom: horizontal ? 2 : (_zone == DropZone.after ? 0 : null),
              width: horizontal ? 2 : null,
              height: horizontal ? null : 2,
              child: IgnorePointer(child: ColoredBox(color: color)),
            ),
        ],
      ),
    );
  }
}

/// A drop area that moves dragged bookmarks to the end of [folderId].
class BookmarkEndDropTarget extends StatefulWidget {
  const BookmarkEndDropTarget({
    super.key,
    required this.tree,
    required this.folderId,
    required this.onDrop,
    required this.child,
  });

  final BookmarkTree tree;
  final int? folderId;
  final void Function(int id) onDrop;
  final Widget child;

  @override
  State<BookmarkEndDropTarget> createState() => _BookmarkEndDropTargetState();
}

class _BookmarkEndDropTargetState extends State<BookmarkEndDropTarget> {
  bool _accept(int id) {
    final folder = widget.folderId;
    return folder == null || !widget.tree.isWithin(folder, id);
  }

  @override
  Widget build(BuildContext context) => DragTarget<BookmarkDrag>(
    onWillAcceptWithDetails: (d) => _accept(d.data.id),
    onAcceptWithDetails: (d) => widget.onDrop(d.data.id),
    builder: (context, candidates, _) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: candidates.isEmpty
            ? null
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: widget.child,
    ),
  );
}
