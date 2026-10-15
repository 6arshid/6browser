import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tabs/tabs_controller.dart';
import '../features/tabs/tabs_state.dart';

const _pinnedWidth = 44.0;
const _minTabWidth = 40.0;
const _maxTabWidth = 220.0;
const stripHeight = 40.0;

/// Desktop tab strip: reorderable, shrinks tabs as more are opened.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final ctl = ref.read(tabsProvider.notifier);
    return SizedBox(
      height: stripHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final unpinned = state.tabs.length - state.pinnedCount;
          final free =
              box.maxWidth - stripHeight - state.pinnedCount * _pinnedWidth;
          final width = unpinned == 0
              ? _maxTabWidth
              : (free / unpinned).clamp(_minTabWidth, _maxTabWidth);
          return Row(
            children: [
              Expanded(
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
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
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'New tab (Ctrl+T)',
                icon: const Icon(Icons.add),
                onPressed: ctl.newTab,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One tab in the strip: title, loading spinner, close button, context menu.
class TabChip extends ConsumerWidget {
  const TabChip({super.key, required this.tab, required this.selected});

  final BrowserTab tab;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(tabsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => ctl.select(tab.id),
      onTertiaryTapUp: (_) => ctl.close(tab.id),
      onSecondaryTapUp: (d) => _menu(context, ctl, d.globalPosition),
      child: Container(
        margin: const EdgeInsets.fromLTRB(2, 4, 2, 0),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([tab.view.title, tab.view.isLoading]),
          builder: (context, _) {
            final title = tab.view.title.value.isEmpty
                ? 'New tab'
                : tab.view.title.value;
            return LayoutBuilder(
              builder: (context, box) {
                // Very narrow tabs show only the icon; close stays reachable via
                // middle-click and the context menu.
                final iconOnly = box.maxWidth < 90;
                return Row(
                  mainAxisAlignment: iconOnly
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (tab.view.isLoading.value)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        tab.pinned ? Icons.push_pin : Icons.public,
                        size: 14,
                      ),
                    if (!tab.pinned && !iconOnly) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                        ),
                      ),
                      InkWell(
                        onTap: () => ctl.close(tab.id),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.close, size: 14),
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    TabsController ctl,
    Offset at,
  ) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        const PopupMenuItem(value: 'dup', child: Text('Duplicate')),
        PopupMenuItem(value: 'pin', child: Text(tab.pinned ? 'Unpin' : 'Pin')),
        const PopupMenuItem(value: 'close', child: Text('Close')),
      ],
    );
    switch (choice) {
      case 'dup':
        ctl.duplicate(tab.id);
      case 'pin':
        ctl.togglePin(tab.id);
      case 'close':
        ctl.close(tab.id);
    }
  }
}

/// Phone-width replacement for the strip: shows tab count and opens a list.
Future<void> showTabSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
                  title: Text('${state.tabs.length} tabs'),
                  trailing: TextButton.icon(
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
                    children: [
                      for (final t in state.tabs)
                        ListTile(
                          selected: t.id == state.activeId,
                          leading: Icon(
                            t.pinned ? Icons.push_pin : Icons.public,
                          ),
                          title: ValueListenableBuilder<String>(
                            valueListenable: t.view.title,
                            builder: (_, title, _) => Text(
                              title.isEmpty ? 'New tab' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: IconButton(
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
