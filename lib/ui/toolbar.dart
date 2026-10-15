import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/browser_engine.dart';
import '../features/tabs/tabs_controller.dart';
import '../features/tabs/url_input.dart';
import 'tab_strip.dart';

/// Below this width the toolbar collapses secondary actions into a menu and
/// the tab strip becomes a tab-count button.
const compactBreakpoint = 720.0;

/// Navigation buttons + address bar for the active tab.
class BrowserToolbar extends ConsumerStatefulWidget {
  const BrowserToolbar({super.key, required this.addressFocus});

  final FocusNode addressFocus;

  @override
  ConsumerState<BrowserToolbar> createState() => _BrowserToolbarState();
}

class _BrowserToolbarState extends ConsumerState<BrowserToolbar> {
  final _address = TextEditingController();
  BrowserView? _bound;

  @override
  void dispose() {
    _bound?.url.removeListener(_syncAddress);
    _address.dispose();
    super.dispose();
  }

  /// Follows the active tab's URL without clobbering what the user types.
  void _bind(BrowserView? view) {
    if (identical(view, _bound)) return;
    _bound?.url.removeListener(_syncAddress);
    _bound = view;
    view?.url.addListener(_syncAddress);
    _address.text = view?.url.value ?? '';
  }

  void _syncAddress() {
    if (!widget.addressFocus.hasFocus) {
      _address.text = _bound?.url.value ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabsProvider);
    final ctl = ref.read(tabsProvider.notifier);
    final view = state.active?.view;
    _bind(view);
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;

    final back = IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: view?.goBack,
    );
    final forward = IconButton(
      tooltip: 'Forward',
      icon: const Icon(Icons.arrow_forward),
      onPressed: view?.goForward,
    );
    final reload = IconButton(
      tooltip: 'Reload',
      icon: const Icon(Icons.refresh),
      onPressed: view?.reload,
    );
    final home = IconButton(
      tooltip: 'Home',
      icon: const Icon(Icons.home_outlined),
      onPressed: view == null ? null : () => view.load(homeUrl),
    );
    final devtools = IconButton(
      tooltip: 'DevTools (F12)',
      icon: const Icon(Icons.developer_mode),
      onPressed: view?.openDevTools,
    );

    final field = Expanded(
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: _address,
          focusNode: widget.addressFocus,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            hintText: 'Search or enter address',
            prefixIcon: view == null
                ? null
                : ValueListenableBuilder<String>(
                    valueListenable: view.url,
                    builder: (_, url, _) => Icon(
                      isSecureUrl(url)
                          ? Icons.lock_outline
                          : Icons.info_outline,
                      size: 18,
                    ),
                  ),
          ),
          onTap: () => _address.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _address.text.length,
          ),
          onSubmitted: (text) {
            view?.load(resolveInput(text));
            widget.addressFocus.unfocus();
          },
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          back,
          if (!compact) forward,
          reload,
          if (!compact) home,
          const SizedBox(width: 4),
          field,
          const SizedBox(width: 4),
          if (compact) _TabCountButton(count: state.tabs.length) else devtools,
          if (compact)
            PopupMenuButton<String>(
              tooltip: 'Menu',
              onSelected: (v) {
                switch (v) {
                  case 'new':
                    ctl.newTab();
                  case 'forward':
                    view?.goForward();
                  case 'home':
                    view?.load(homeUrl);
                  case 'devtools':
                    view?.openDevTools();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text('New tab')),
                PopupMenuItem(value: 'forward', child: Text('Forward')),
                PopupMenuItem(value: 'home', child: Text('Home')),
                PopupMenuItem(value: 'devtools', child: Text('DevTools')),
              ],
            ),
        ],
      ),
    );
  }
}

class _TabCountButton extends ConsumerWidget {
  const _TabCountButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Tabs',
    onPressed: () => showTabSheet(context, ref),
    icon: Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          width: 2,
          color: IconTheme.of(context).color ?? Colors.grey,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$count', style: const TextStyle(fontSize: 12)),
    ),
  );
}
