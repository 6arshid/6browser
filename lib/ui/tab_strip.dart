import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/browser_engine.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/tabs_state.dart';
import '../features/tabs/url_input.dart';
import 'browser_theme.dart';
import 'favicon.dart';

const _pinnedWidth = 44.0;
const _minTabWidth = 44.0;
const _maxTabWidth = 232.0;
const _tabGap = 2.0;
const stripHeight = 40.0;

/// Desktop tab strip in Safari's style: tabs are rounded cards on the window
/// frame, the selected one raised with a soft shadow. Tabs are reorderable
/// and shrink as more are opened.
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
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 3),
      child: LayoutBuilder(
        builder: (context, box) {
          final unpinned = state.tabs.length - state.pinnedCount;
          // New-tab button and gaps.
          final free =
              box.maxWidth -
              40 -
              state.tabs.length * _tabGap -
              state.pinnedCount * _pinnedWidth;
          final width = unpinned == 0
              ? _maxTabWidth
              : (free / unpinned).clamp(_minTabWidth, _maxTabWidth);
          return Row(
            children: [
              Flexible(
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
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
                        child: Padding(
                          padding: const EdgeInsets.only(right: _tabGap),
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
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              _StripButton(
                tooltip: 'New tab (Ctrl+T)',
                icon: CupertinoIcons.add,
                color: colors.tabBackgroundText,
                onPressed: ctl.newTab,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A small square button on the tab strip.
class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    iconSize: 17,
    color: color,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    icon: Icon(icon),
    onPressed: onPressed,
  );
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
    final palette = incognito && selected ? BrowserColors.incognito : themed;
    final text = selected ? palette.tabText : themed.tabBackgroundText;
    final brightness = ThemeData.estimateBrightnessForColor(themed.frame);
    final fill = selected
        ? palette.toolbar
        : _hover
        ? themed.tabText.withValues(alpha: 0.06)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => ctl.select(tab.id),
        onTertiaryTapUp: (_) => ctl.close(tab.id),
        onSecondaryTapUp: (d) => _menu(context, ctl, d.globalPosition),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: Ui.fast,
              curve: Ui.curve,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(Ui.radius),
                boxShadow: selected
                    ? Ui.shadow(brightness, strength: 0.5)
                    : null,
                border: selected
                    ? Border.all(
                        color: themed.separator.withValues(alpha: 0.06),
                        width: 0.5,
                      )
                    : null,
              ),
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  tab.view.title,
                  tab.view.url,
                  tab.view.isLoading,
                ]),
                builder: (context, _) => Tooltip(
                  message: tabTitle(tab.view),
                  waitDuration: const Duration(milliseconds: 800),
                  child: LayoutBuilder(
                    builder: (context, box) => _content(
                      ctl,
                      text,
                      selected: selected,
                      iconOnly: box.maxWidth < 72,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showSeparator && !_hover)
              Positioned(
                right: -_tabGap / 2 - 0.5,
                top: 9,
                bottom: 9,
                child: Container(width: 1, color: themed.separator),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    TabsController ctl,
    Color text, {
    required bool selected,
    required bool iconOnly,
  }) {
    final view = tab.view;
    final Widget icon = view.isLoading.value
        ? SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: text),
          )
        : view.incognito
        ? Icon(CupertinoIcons.eye_slash, size: 15, color: text)
        : Favicon(url: view.url.value, color: text);
    if (tab.pinned || iconOnly) {
      // Very narrow tabs show only the icon; close stays reachable through
      // middle-click and the context menu.
      return Center(child: icon);
    }
    final showClose = selected || _hover;
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: ShaderMask(
              // Fade the end of long titles instead of an ellipsis.
              shaderCallback: (r) => LinearGradient(
                colors: const [Colors.white, Colors.white, Colors.transparent],
                stops: [0, ((r.width - 20) / r.width).clamp(0.0, 1.0), 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: Text(
                tabTitle(view),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 12.5,
                  color: text,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: Ui.fast,
            opacity: showClose ? 1 : 0,
            child: IgnorePointer(
              ignoring: !showClose,
              child: IconButton(
                tooltip: 'Close tab (Ctrl+W)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 20,
                  height: 20,
                ),
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                iconSize: 11,
                color: text,
                icon: const Icon(CupertinoIcons.xmark),
                onPressed: () => ctl.close(tab.id),
              ),
            ),
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
          height: 32,
          child: Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 12),
              Text(label),
            ],
          ),
        );
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        item('new', CupertinoIcons.add, 'New tab'),
        const PopupMenuDivider(),
        item('reload', CupertinoIcons.arrow_clockwise, 'Reload'),
        item('dup', CupertinoIcons.square_on_square, 'Duplicate'),
        item(
          'pin',
          tab.pinned ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
          tab.pinned ? 'Unpin' : 'Pin',
        ),
        const PopupMenuDivider(),
        item('close', CupertinoIcons.xmark, 'Close'),
        item('others', CupertinoIcons.xmark_square, 'Close other tabs'),
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

/// Title shown for a tab; blank pages and the New Tab page read "New tab".
String tabTitle(BrowserView view) =>
    isNewTabUrl(view.url.value) || view.title.value.isEmpty
    ? 'New tab'
    : view.title.value;
