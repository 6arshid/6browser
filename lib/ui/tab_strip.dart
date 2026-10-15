import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/browser_engine.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/tabs_state.dart';
import '../features/tabs/url_input.dart';
import 'browser_theme.dart';
import 'favicon.dart';

const _pinnedWidth = 48.0;
const _minTabWidth = 44.0;
const _maxTabWidth = 240.0;

/// Width of the curve that joins the selected tab to the toolbar.
const _flare = 8.0;
const stripHeight = 42.0;

/// Desktop tab strip, Chrome style: the selected tab merges into the
/// toolbar; tabs are reorderable and shrink as more are opened.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final ctl = ref.read(tabsProvider.notifier);
    final colors = BrowserColors.of(context);
    return Container(
      height: stripHeight,
      decoration: BoxDecoration(
        color: colors.frame,
        image: colors.frameImage == null
            ? null
            : DecorationImage(
                image: colors.frameImage!,
                alignment: Alignment.topLeft,
                repeat: ImageRepeat.repeat,
                fit: BoxFit.none,
              ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final unpinned = state.tabs.length - state.pinnedCount;
          // Logo, new-tab button and the list's side padding.
          final free =
              box.maxWidth -
              40 -
              44 -
              2 * _flare -
              state.pinnedCount * _pinnedWidth;
          final width = unpinned == 0
              ? _maxTabWidth
              : (free / unpinned).clamp(_minTabWidth, _maxTabWidth);
          return Row(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 6, 0),
                child: Image.asset('assets/logo.png', width: 22, height: 22),
              ),
              Flexible(
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: _flare),
                  clipBehavior: Clip.none,
                  buildDefaultDragHandles: false,
                  onReorderItem: ctl.reorder,
                  proxyDecorator: (child, _, _) =>
                      Material(color: Colors.transparent, child: child),
                  children: [
                    for (var i = 0; i < state.tabs.length; i++)
                      ReorderableDragStartListener(
                        key: ValueKey(state.tabs[i].id),
                        index: i,
                        child: SizedBox(
                          width: state.tabs[i].pinned ? _pinnedWidth : width,
                          child: TabChip(
                            tab: state.tabs[i],
                            selected: state.tabs[i].id == state.activeId,
                            showSeparator:
                                i < state.tabs.length - 1 &&
                                state.tabs[i].id != state.activeId &&
                                state.tabs[i + 1].id != state.activeId,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IconButton(
                  tooltip: 'New tab (Ctrl+T)',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  color: colors.tabBackgroundText,
                  icon: const Icon(Icons.add),
                  onPressed: ctl.newTab,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One tab: favicon or spinner, title, close button and a context menu.
class TabChip extends ConsumerStatefulWidget {
  const TabChip({
    super.key,
    required this.tab,
    required this.selected,
    this.showSeparator = false,
  });

  final BrowserTab tab;
  final bool selected;

  /// Draws the thin divider on the right, between two unselected tabs.
  final bool showSeparator;

  @override
  ConsumerState<TabChip> createState() => _TabChipState();
}

class _TabChipState extends ConsumerState<TabChip> {
  bool _hover = false;

  BrowserTab get tab => widget.tab;

  @override
  Widget build(BuildContext context) {
    final ctl = ref.read(tabsProvider.notifier);
    final themed = BrowserColors.of(context);
    final incognito = tab.view.incognito;
    final selected = widget.selected;
    // The selected tab takes the toolbar's color, which is dark for private
    // tabs.
    final fill = selected
        ? (incognito ? BrowserColors.incognito.toolbar : themed.toolbar)
        : null;
    final text = selected
        ? (incognito ? BrowserColors.incognito.tabText : themed.tabText)
        : themed.tabBackgroundText;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => ctl.select(tab.id),
        onTertiaryTapUp: (_) => ctl.close(tab.id),
        onSecondaryTapUp: (d) => _menu(context, ctl, d.globalPosition),
        child: CustomPaint(
          painter: _TabPainter(
            fill: fill,
            hover: !selected && _hover
                ? themed.tabBackgroundText.withValues(alpha: 0.10)
                : null,
            separator: widget.showSeparator && !_hover
                ? themed.separator
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: ListenableBuilder(
              listenable: Listenable.merge([
                tab.view.title,
                tab.view.url,
                tab.view.isLoading,
              ]),
              builder: (context, _) => Tooltip(
                message: tabTitle(tab.view),
                waitDuration: const Duration(milliseconds: 700),
                child: LayoutBuilder(
                  builder: (context, box) =>
                      _content(ctl, text, iconOnly: box.maxWidth < 72),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(TabsController ctl, Color text, {required bool iconOnly}) {
    final view = tab.view;
    final Widget icon = view.isLoading.value
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: text),
          )
        : view.incognito
        ? Icon(Icons.visibility_off, size: 16, color: text)
        : Favicon(url: view.url.value, color: text);
    if (tab.pinned || iconOnly) {
      // Very narrow tabs show only the icon; close stays reachable through
      // middle-click and the context menu.
      return Center(child: icon);
    }
    final showClose = widget.selected || _hover;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: ShaderMask(
              // Fade the end of long titles instead of an ellipsis.
              shaderCallback: (r) => LinearGradient(
                colors: const [Colors.white, Colors.white, Colors.transparent],
                stops: [0, ((r.width - 24) / r.width).clamp(0.0, 1.0), 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: Text(
                tabTitle(view),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(fontSize: 12.5, color: text),
              ),
            ),
          ),
          SizedBox(
            width: 22,
            height: 22,
            child: showClose
                ? IconButton(
                    tooltip: 'Close tab (Ctrl+W)',
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    color: text,
                    icon: const Icon(Icons.close),
                    onPressed: () => ctl.close(tab.id),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    TabsController ctl,
    Offset at,
  ) async {
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          height: 40,
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 12),
              Text(label),
            ],
          ),
        );
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        item('new', Icons.add, 'New tab'),
        const PopupMenuDivider(),
        item('reload', Icons.refresh, 'Reload'),
        item('dup', Icons.copy_all_outlined, 'Duplicate'),
        item(
          'pin',
          tab.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          tab.pinned ? 'Unpin' : 'Pin',
        ),
        const PopupMenuDivider(),
        item('close', Icons.close, 'Close'),
        item('others', Icons.tab_unselected, 'Close other tabs'),
      ],
    );
    switch (choice) {
      case 'new':
        ctl.newTab();
      case 'reload':
        tab.view.reload();
      case 'dup':
        ctl.duplicate(tab.id);
      case 'pin':
        ctl.togglePin(tab.id);
      case 'close':
        ctl.close(tab.id);
      case 'others':
        for (final t in ref.read(tabsProvider).tabs.toList()) {
          if (t.id != tab.id) ctl.close(t.id);
        }
    }
  }
}

/// Selected tab: rounded top corners and outward curves at the bottom that
/// join the toolbar. Unselected tabs: a hover pill and a divider.
class _TabPainter extends CustomPainter {
  const _TabPainter({this.fill, this.hover, this.separator});

  final Color? fill;
  final Color? hover;
  final Color? separator;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 6.0;
    const r = 8.0;
    final w = size.width;
    final h = size.height;
    if (fill != null) {
      final path = Path()
        ..moveTo(-_flare, h)
        ..arcToPoint(
          Offset(0, h - _flare),
          radius: const Radius.circular(_flare),
          clockwise: false,
        )
        ..lineTo(0, top + r)
        ..arcToPoint(Offset(r, top), radius: const Radius.circular(r))
        ..lineTo(w - r, top)
        ..arcToPoint(Offset(w, top + r), radius: const Radius.circular(r))
        ..lineTo(w, h - _flare)
        ..arcToPoint(
          Offset(w + _flare, h),
          radius: const Radius.circular(_flare),
          clockwise: false,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = fill!);
      return;
    }
    if (hover != null) {
      canvas.drawRRect(
        RRect.fromLTRBR(2, top + 2, w - 2, h - 4, const Radius.circular(8)),
        Paint()..color = hover!,
      );
    }
    if (separator != null) {
      canvas.drawLine(
        Offset(w - 0.5, top + 9),
        Offset(w - 0.5, h - 9),
        Paint()
          ..color = separator!
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_TabPainter old) =>
      old.fill != fill || old.hover != hover || old.separator != separator;
}

/// Phone-width replacement for the strip: shows tab count and opens a list.
Future<void> showTabSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(tabsProvider);
        final ctl = ref.read(tabsProvider.notifier);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    '${state.tabs.length} tabs',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  trailing: FilledButton.tonalIcon(
                    icon: const Icon(Icons.add),
                    label: const Text('New tab'),
                    onPressed: () {
                      ctl.newTab();
                      Navigator.pop(context);
                    },
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final t in state.tabs)
                        ListTile(
                          selected: t.id == state.activeId,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          leading: t.view.incognito
                              ? const Icon(Icons.visibility_off)
                              : t.pinned
                              ? const Icon(Icons.push_pin)
                              : Favicon(url: t.view.url.value, size: 20),
                          title: ListenableBuilder(
                            listenable: Listenable.merge([
                              t.view.title,
                              t.view.url,
                            ]),
                            builder: (_, _) => Text(
                              tabTitle(t.view),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Close tab',
                            icon: const Icon(Icons.close),
                            onPressed: () => ctl.close(t.id),
                          ),
                          onTap: () {
                            ctl.select(t.id);
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Title shown for a tab; blank pages and the New Tab page read "New tab".
String tabTitle(BrowserView view) =>
    isNewTabUrl(view.url.value) || view.title.value.isEmpty
    ? 'New tab'
    : view.title.value;
