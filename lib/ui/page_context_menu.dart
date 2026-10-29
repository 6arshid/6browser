import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/browser_engine.dart';
import '../features/settings/app_settings.dart';
import '../features/tabs/tabs_controller.dart';

/// Shows the app's own right-click menu for [view]'s page. The engine
/// renders off-screen and cannot show a native menu, so it reports what was
/// under the pointer (link, image, selection, text field) and this draws a
/// Chrome-like menu for it.
class PageContextMenuHost extends ConsumerStatefulWidget {
  const PageContextMenuHost({
    super.key,
    required this.view,
    required this.child,
  });

  final BrowserView view;
  final Widget child;

  @override
  ConsumerState<PageContextMenuHost> createState() =>
      _PageContextMenuHostState();
}

class _PageContextMenuHostState extends ConsumerState<PageContextMenuHost> {
  StreamSubscription<PageContextMenu>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.view.contextMenus.listen(_show);
  }

  @override
  void didUpdateWidget(PageContextMenuHost old) {
    super.didUpdateWidget(old);
    if (old.view != widget.view) {
      _sub?.cancel();
      _sub = widget.view.contextMenus.listen(_show);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _show(PageContextMenu m) async {
    if (!mounted) return;
    final entries = pageMenuEntries(m);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(m.position);
    final action = await showMenu<PageMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      items: [
        for (final e in entries)
          if (e == null)
            const PopupMenuDivider()
          else
            PopupMenuItem<PageMenuAction>(
              value: e.action,
              enabled: e.enabled,
              height: 30,
              child: _EntryRow(entry: e),
            ),
      ],
    );
    if (action != null && mounted) _run(action, m);
  }

  void _run(PageMenuAction action, PageContextMenu m) {
    final view = widget.view;
    final tabs = ref.read(tabsProvider.notifier);
    void copy(String text) => Clipboard.setData(ClipboardData(text: text));
    switch (action) {
      case PageMenuAction.back:
        view.goBack();
      case PageMenuAction.forward:
        view.goForward();
      case PageMenuAction.reload:
        view.reload();
      case PageMenuAction.openLinkInNewTab:
        final opener = ref
            .read(tabsProvider)
            .tabs
            .where((t) => identical(t.view, view))
            .firstOrNull;
        if (opener != null) {
          tabs.openFromTab(opener.id, m.linkUrl, background: true);
        } else {
          tabs.newTab(
            url: m.linkUrl,
            activate: false,
            incognito: view.incognito,
          );
        }
      case PageMenuAction.openLinkInIncognito:
        tabs.newTab(url: m.linkUrl, incognito: true);
      case PageMenuAction.saveLink:
        view.download(m.linkUrl);
      case PageMenuAction.copyLink:
        copy(m.linkUrl);
      case PageMenuAction.openImageInNewTab:
        tabs.newTab(
          url: m.imageUrl,
          activate: false,
          incognito: view.incognito,
        );
      case PageMenuAction.saveImage:
        view.download(m.imageUrl);
      case PageMenuAction.copyImageAddress:
        copy(m.imageUrl);
      case PageMenuAction.searchSelection:
        final template = ref.read(appSettingsProvider).searchTemplate;
        tabs.newTab(
          url: template.replaceAll(
            '%s',
            Uri.encodeQueryComponent(m.selectionText.trim()),
          ),
          incognito: view.incognito,
        );
      case PageMenuAction.undo:
        view.editCommand(EditCommand.undo);
      case PageMenuAction.redo:
        view.editCommand(EditCommand.redo);
      case PageMenuAction.cut:
        view.editCommand(EditCommand.cut);
      case PageMenuAction.copy:
        view.editCommand(EditCommand.copy);
      case PageMenuAction.paste:
        view.editCommand(EditCommand.paste);
      case PageMenuAction.selectAll:
        view.editCommand(EditCommand.selectAll);
      case PageMenuAction.viewSource:
        tabs.newTab(url: 'view-source:${m.pageUrl}', incognito: view.incognito);
      case PageMenuAction.inspect:
        view.inspectAt(m.pagePosition);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum PageMenuAction {
  back,
  forward,
  reload,
  openLinkInNewTab,
  openLinkInIncognito,
  saveLink,
  copyLink,
  openImageInNewTab,
  saveImage,
  copyImageAddress,
  searchSelection,
  undo,
  redo,
  cut,
  copy,
  paste,
  selectAll,
  viewSource,
  inspect,
}

class PageMenuEntry {
  const PageMenuEntry(
    this.action,
    this.label, {
    this.shortcut = '',
    this.icon,
    this.enabled = true,
  });

  final PageMenuAction action;
  final String label;
  final String shortcut;
  final IconData? icon;
  final bool enabled;
}

/// The menu for [m], top to bottom; `null` is a divider. Like Chrome, the
/// sections depend on what was clicked, and Reload is always there.
List<PageMenuEntry?> pageMenuEntries(PageContextMenu m) {
  final sections = <List<PageMenuEntry>>[];
  final hasLink = m.linkUrl.isNotEmpty;
  final hasImage = m.imageUrl.isNotEmpty;
  final selection = m.selectionText.trim();

  if (hasLink) {
    sections.add(const [
      PageMenuEntry(
        PageMenuAction.openLinkInNewTab,
        'Open link in new tab',
        icon: CupertinoIcons.plus_square_on_square,
      ),
      PageMenuEntry(
        PageMenuAction.openLinkInIncognito,
        'Open link in incognito tab',
        icon: CupertinoIcons.eye_slash,
      ),
    ]);
    sections.add(const [
      PageMenuEntry(PageMenuAction.saveLink, 'Save link as...'),
      PageMenuEntry(
        PageMenuAction.copyLink,
        'Copy link address',
        icon: CupertinoIcons.link,
      ),
    ]);
  }
  if (hasImage) {
    sections.add(const [
      PageMenuEntry(
        PageMenuAction.openImageInNewTab,
        'Open image in new tab',
        icon: CupertinoIcons.photo,
      ),
      PageMenuEntry(
        PageMenuAction.saveImage,
        'Save image as...',
        icon: CupertinoIcons.arrow_down_circle,
      ),
      PageMenuEntry(PageMenuAction.copyImageAddress, 'Copy image address'),
    ]);
  }
  if (m.isEditable) {
    sections.add([
      PageMenuEntry(
        PageMenuAction.undo,
        'Undo',
        shortcut: 'Ctrl+Z',
        icon: CupertinoIcons.arrow_uturn_left,
        enabled: m.canUndo,
      ),
      PageMenuEntry(
        PageMenuAction.redo,
        'Redo',
        shortcut: 'Ctrl+Y',
        icon: CupertinoIcons.arrow_uturn_right,
        enabled: m.canRedo,
      ),
    ]);
    sections.add([
      PageMenuEntry(
        PageMenuAction.cut,
        'Cut',
        shortcut: 'Ctrl+X',
        icon: CupertinoIcons.scissors,
        enabled: m.canCut,
      ),
      PageMenuEntry(
        PageMenuAction.copy,
        'Copy',
        shortcut: 'Ctrl+C',
        icon: CupertinoIcons.doc_on_doc,
        enabled: m.canCopy,
      ),
      PageMenuEntry(
        PageMenuAction.paste,
        'Paste',
        shortcut: 'Ctrl+V',
        icon: CupertinoIcons.doc_on_clipboard,
        enabled: m.canPaste,
      ),
      PageMenuEntry(
        PageMenuAction.selectAll,
        'Select all',
        shortcut: 'Ctrl+A',
        icon: CupertinoIcons.selection_pin_in_out,
        enabled: m.canSelectAll,
      ),
    ]);
  } else if (selection.isNotEmpty) {
    final quoted = selection.length > 24
        ? '${selection.substring(0, 24)}…'
        : selection;
    sections.add([
      const PageMenuEntry(
        PageMenuAction.copy,
        'Copy',
        shortcut: 'Ctrl+C',
        icon: CupertinoIcons.doc_on_doc,
      ),
      PageMenuEntry(
        PageMenuAction.searchSelection,
        'Search for “$quoted”',
        icon: CupertinoIcons.search,
      ),
    ]);
  }

  // Back / Forward / Reload: always at hand, like Chrome's page menu.
  sections.add([
    if (!hasLink && !hasImage && !m.isEditable && selection.isEmpty) ...[
      PageMenuEntry(
        PageMenuAction.back,
        'Back',
        shortcut: 'Alt+Left',
        icon: CupertinoIcons.chevron_left,
        enabled: m.canGoBack,
      ),
      PageMenuEntry(
        PageMenuAction.forward,
        'Forward',
        shortcut: 'Alt+Right',
        icon: CupertinoIcons.chevron_right,
        enabled: m.canGoForward,
      ),
    ],
    const PageMenuEntry(
      PageMenuAction.reload,
      'Reload',
      shortcut: 'Ctrl+R',
      icon: CupertinoIcons.arrow_clockwise,
    ),
  ]);
  sections.add([
    if (m.pageUrl.startsWith('http'))
      const PageMenuEntry(
        PageMenuAction.viewSource,
        'View page source',
        icon: CupertinoIcons.chevron_left_slash_chevron_right,
      ),
    const PageMenuEntry(
      PageMenuAction.inspect,
      'Inspect',
      shortcut: 'F12',
      icon: CupertinoIcons.hammer,
    ),
  ]);

  return [
    for (final (i, s) in sections.indexed) ...[if (i > 0) null, ...s],
  ];
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final PageMenuEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: entry.icon == null ? null : Icon(entry.icon, size: 18),
        ),
        Expanded(child: Text(entry.label, overflow: TextOverflow.ellipsis)),
        if (entry.shortcut.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              entry.shortcut,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
      ],
    );
  }
}
