import 'dart:async';

import 'package:browser6/engine/browser_engine.dart';
import 'package:flutter/widgets.dart';

class FakeView implements BrowserView {
  FakeView(String initial, {this.incognito = false})
    : url = ValueNotifier(initial);

  @override
  final bool incognito;
  bool disposed = false;
  @override
  final ValueNotifier<String> url;
  @override
  final ValueNotifier<String> title = ValueNotifier('');
  @override
  final ValueNotifier<bool> isLoading = ValueNotifier(false);
  @override
  final ValueNotifier<bool> isReady = ValueNotifier(true);
  @override
  Widget get widget => const SizedBox();
  @override
  bool get supportsStop => false;
  @override
  Future<void> load(String url) async => this.url.value = url;
  @override
  Future<void> goBack() async {}
  @override
  Future<void> goForward() async {}
  int reloads = 0;
  @override
  Future<void> reload() async => reloads++;
  @override
  Future<void> stop() async {}
  int hardReloads = 0;
  @override
  Future<void> reloadIgnoringCache() async => hardReloads++;
  @override
  Future<void> openDevTools() async {}
  @override
  bool get supportsPageTools => true;
  @override
  final ValueNotifier<double> zoom = ValueNotifier(1);
  @override
  Future<void> zoomStep(int direction) async => zoom.value = direction == 0
      ? 1
      : zoom.value * (direction > 0 ? 1.1 : 1 / 1.1);
  final finds = <String>[];
  @override
  Future<void> find(
    String text, {
    bool forward = true,
    bool findNext = false,
  }) async {
    finds.add('${forward ? '>' : '<'}${findNext ? '+' : ''}$text');
    findResult.value = FindResult(count: 3, active: forward ? 1 : 3);
  }

  bool findStopped = false;
  @override
  Future<void> stopFinding() async => findStopped = true;
  @override
  final ValueNotifier<FindResult> findResult = ValueNotifier(FindResult.none);
  int prints = 0;
  @override
  Future<void> printPage() async => prints++;
  final contextMenuController = StreamController<PageContextMenu>.broadcast();
  final editCommands = <EditCommand>[];
  final downloads = <String>[];
  @override
  Stream<PageContextMenu> get contextMenus => contextMenuController.stream;
  @override
  Future<void> editCommand(EditCommand command) async =>
      editCommands.add(command);
  @override
  Future<void> download(String url) async => downloads.add(url);
  @override
  Future<void> inspectAt(Offset pagePosition) async {}
  /// Scripts run in the page, and messages the page sends back.
  final scripts = <String>[];
  final scriptController = StreamController<String>.broadcast();
  @override
  Future<void> runScript(String script) async => scripts.add(script);
  @override
  String get scriptPostFunction => 'function (m) { fakePost(m); }';
  @override
  Stream<String> get scriptMessages => scriptController.stream;

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeEngine implements BrowserEngine {
  final downloadController = StreamController<DownloadEvent>.broadcast();

  @override
  Stream<DownloadEvent> get downloads => downloadController.stream;

  @override
  Future<void> initialize() async {}
  @override
  BrowserView createView({
    required String initialUrl,
    bool incognito = false,
  }) => FakeView(initialUrl, incognito: incognito);
  @override
  Future<void> shutdown() async {}
}
