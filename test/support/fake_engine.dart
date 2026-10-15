import 'dart:async';

import 'package:browser6/engine/browser_engine.dart';
import 'package:flutter/widgets.dart';

class FakeView implements BrowserView {
  FakeView(String initial) : url = ValueNotifier(initial);
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
  @override
  Future<void> reload() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> openDevTools() async {}
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
  BrowserView createView({required String initialUrl}) => FakeView(initialUrl);
  @override
  Future<void> shutdown() async {}
}
