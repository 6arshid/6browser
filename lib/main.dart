import 'package:flutter/material.dart';

import 'engine/browser_engine.dart';
import 'engine/cef_engine.dart';
import 'features/tabs/url_input.dart';

const homeUrl = 'https://www.google.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SixBrowserApp());
}

class SixBrowserApp extends StatelessWidget {
  const SixBrowserApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '6browser',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const BrowserPage(),
  );
}

/// Step 3: a single-tab browser. Multi-tab arrives in step 4.
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final BrowserEngine _engine = CefEngine();
  final _address = TextEditingController();
  BrowserView? _view;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _engine.initialize();
    if (!mounted) return;
    final view = _engine.createView(initialUrl: homeUrl);
    view.url.addListener(() => _address.text = view.url.value);
    setState(() => _view = view);
  }

  @override
  void dispose() {
    _view?.dispose();
    _engine.shutdown();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return Scaffold(
      body: Column(
        children: [
          _Toolbar(view: view, address: _address),
          Expanded(
            child: view == null
                ? const Center(child: CircularProgressIndicator())
                : ValueListenableBuilder<bool>(
                    valueListenable: view.isReady,
                    builder: (_, ready, _) => ready
                        ? view.widget
                        : const Center(child: CircularProgressIndicator()),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.view, required this.address});

  final BrowserView? view;
  final TextEditingController address;

  @override
  Widget build(BuildContext context) {
    final v = view;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: v?.goBack,
          ),
          IconButton(
            tooltip: 'Forward',
            icon: const Icon(Icons.arrow_forward),
            onPressed: v?.goForward,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: v?.reload,
          ),
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: v == null ? null : () => v.load(homeUrl),
          ),
          Expanded(
            child: TextField(
              controller: address,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: 'Search or enter address',
                prefixIcon: v == null
                    ? null
                    : ValueListenableBuilder<String>(
                        valueListenable: v.url,
                        builder: (_, url, _) => Icon(
                          isSecureUrl(url)
                              ? Icons.lock_outline
                              : Icons.info_outline,
                          size: 18,
                        ),
                      ),
              ),
              onSubmitted: (text) => v?.load(resolveInput(text)),
            ),
          ),
          IconButton(
            tooltip: 'DevTools',
            icon: const Icon(Icons.developer_mode),
            onPressed: v?.openDevTools,
          ),
        ],
      ),
    );
  }
}
