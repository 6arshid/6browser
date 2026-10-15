import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tabs/tabs_controller.dart';
import 'tab_strip.dart';
import 'toolbar.dart';

/// Main window: tab strip (wide) or tab button (narrow), toolbar, page area.
class BrowserShell extends ConsumerStatefulWidget {
  const BrowserShell({super.key});

  @override
  ConsumerState<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends ConsumerState<BrowserShell> {
  final _addressFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Provider state may not be modified while the tree is building.
    Future.microtask(() => ref.read(tabsProvider.notifier).start());
  }

  @override
  void dispose() {
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final ctl = ref.read(tabsProvider.notifier);
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            ctl.newTab,
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): ctl.newIncognitoTab,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          final a = state.active;
          if (a != null) ctl.close(a.id);
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _addressFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): ctl.cycle,
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): () =>
            ctl.cycle(delta: -1),
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            state.active?.view.openDevTools(),
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            state.active?.view.reload(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                if (!compact) const TabStrip(),
                BrowserToolbar(addressFocus: _addressFocus),
                Expanded(
                  child: state.tabs.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : IndexedStack(
                          index: state.activeIndex,
                          children: [
                            for (final t in state.tabs)
                              KeyedSubtree(
                                key: ValueKey(t.id),
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: t.view.isReady,
                                  builder: (_, ready, _) => ready
                                      ? t.view.widget
                                      : const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                ),
                              ),
                          ],
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
