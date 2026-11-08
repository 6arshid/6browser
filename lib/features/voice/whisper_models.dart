import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../data/system_proxy.dart';
import 'speech_input.dart';

/// The Whisper models voice commands can use on Windows (whisper.cpp's
/// ggml files). Sizes and hashes pin the exact files.
enum WhisperModel {
  standard(
    label: 'Standard',
    detail: 'Fast. Good for English and everyday Persian commands.',
    file: 'ggml-small-q5_1.bin',
    bytes: 190085487,
    sha256: 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    audioContext: 512,
  ),
  accurate(
    label: 'Accurate',
    detail: 'Understands Persian better, but takes a few seconds per command.',
    file: 'ggml-large-v3-turbo-q5_0.bin',
    bytes: 574041195,
    sha256: '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
    // Turbo starts repeating itself below ~640.
    audioContext: 768,
  );

  const WhisperModel({
    required this.label,
    required this.detail,
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.audioContext,
  });

  final String label;
  final String detail;
  final String file;
  final int bytes;
  final String sha256;
  final int audioContext;

  String get url =>
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file';

  String get size => '${(bytes / 1000000).round()} MB';

  static WhisperModel fromName(String? name) => values.firstWhere(
    (m) => m.name == name,
    orElse: () => WhisperModel.standard,
  );
}

/// Folder for the models, shared by every profile. Overridden in tests.
final speechModelsDirProvider = Provider<Future<Directory>>(
  (ref) async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'speech'),
  ),
);

final whisperModelsProvider =
    NotifierProvider<WhisperModels, WhisperModelsState>(WhisperModels.new);

class WhisperModelsState {
  const WhisperModelsState({
    this.folder,
    this.installed = const {},
    this.downloading,
    this.received = 0,
    this.verifying = false,
    this.error,
  });

  /// Null until the folder has been looked at.
  final String? folder;
  final Set<WhisperModel> installed;

  /// The model being downloaded (or checked after import).
  final WhisperModel? downloading;
  final int received;

  /// Checking the file's hash after the download.
  final bool verifying;

  /// Why the last download or import failed.
  final String? error;

  bool get busy => downloading != null || verifying;

  double? get progress {
    final model = downloading;
    return model == null || verifying ? null : received / model.bytes;
  }

  WhisperModelFile? fileOf(WhisperModel model) {
    final dir = folder;
    if (dir == null || !installed.contains(model)) return null;
    return WhisperModelFile(p.join(dir, model.file), model.audioContext);
  }
}

/// Downloads, imports and deletes the speech models.
class WhisperModels extends Notifier<WhisperModelsState> {
  HttpClient? _client;
  bool _cancelled = false;

  @override
  WhisperModelsState build() {
    _scan();
    return const WhisperModelsState();
  }

  Future<Directory> get _dir => ref.read(speechModelsDirProvider);

  Future<void> _scan() async {
    final Directory dir;
    final installed = <WhisperModel>{};
    try {
      dir = await _dir;
      for (final model in WhisperModel.values) {
        final file = File(p.join(dir.path, model.file));
        if (await file.exists() && await file.length() == model.bytes) {
          installed.add(model);
        }
      }
    } on Object catch (e) {
      // Checked, though nothing is installed: the panel then shows why.
      state = WhisperModelsState(
        folder: '',
        error: 'The speech model folder cannot be read ($e).',
      );
      return;
    }
    state = WhisperModelsState(
      folder: dir.path,
      installed: installed,
      downloading: state.downloading,
      received: state.received,
      verifying: state.verifying,
      error: state.error,
    );
  }

  void _update({
    WhisperModel? downloading,
    int received = 0,
    bool verifying = false,
    String? error,
    Set<WhisperModel>? installed,
  }) {
    state = WhisperModelsState(
      folder: state.folder,
      installed: installed ?? state.installed,
      downloading: downloading,
      received: received,
      verifying: verifying,
      error: error,
    );
  }

  /// Downloads [model], continuing a download that was interrupted.
  Future<void> download(WhisperModel model) async {
    if (state.busy) return;
    _cancelled = false;
    _update(downloading: model);
    final client = _client = HttpClient()
      ..findProxy = systemProxyFinder()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final dir = await _dir;
      await dir.create(recursive: true);
      final part = File(p.join(dir.path, '${model.file}.part'));
      var start = await part.exists() ? await part.length() : 0;
      if (start >= model.bytes) {
        await part.delete();
        start = 0;
      }
      final request = await client.getUrl(Uri.parse(model.url));
      if (start > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
      }
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        start = 0; // the server sent the whole file
      } else if (response.statusCode != HttpStatus.partialContent) {
        throw HttpException('the server answered ${response.statusCode}');
      }
      final sink = part.openWrite(
        mode: start == 0 ? FileMode.write : FileMode.append,
      );
      var received = start;
      final clock = Stopwatch()..start();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (clock.elapsedMilliseconds > 150) {
            clock.reset();
            _update(downloading: model, received: received);
          }
        }
      } finally {
        await sink.close();
      }
      if (received != model.bytes) {
        throw const HttpException('the download was cut short');
      }
      await _install(part, model);
    } catch (e) {
      _update(
        error: _cancelled
            ? null
            : 'The model could not be downloaded (${_describe(e)}). Check '
                  'the connection, or download ${model.file} in a browser '
                  'and choose it with "Choose file".',
      );
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }

  void cancelDownload() {
    _cancelled = true;
    _client?.close(force: true);
  }

  /// Installs a model file the user downloaded elsewhere. Returns the model
  /// it is, or null when it is not one of [WhisperModel] (the reason is in
  /// [WhisperModelsState.error]).
  Future<WhisperModel?> importFile(String path) async {
    if (state.busy) return null;
    final source = File(path);
    final length = await source.length();
    final model = WhisperModel.values
        .where((m) => m.bytes == length)
        .firstOrNull;
    if (model == null) {
      _update(
        error:
            'That file is not a supported model. Choose '
            '${WhisperModel.values.map((m) => m.file).join(' or ')}.',
      );
      return null;
    }
    try {
      final dir = await _dir;
      await dir.create(recursive: true);
      final part = await source.copy(p.join(dir.path, '${model.file}.part'));
      return await _install(part, model) ? model : null;
    } catch (e) {
      _update(error: 'The model could not be copied (${_describe(e)}).');
      return null;
    }
  }

  /// Checks the downloaded [part] against [model]'s hash and puts it in
  /// place.
  Future<bool> _install(File part, WhisperModel model) async {
    _update(downloading: model, received: model.bytes, verifying: true);
    final path = part.path;
    final hash = await Isolate.run(() => _sha256Of(path));
    if (hash != model.sha256) {
      await part.delete();
      _update(
        error: 'The model file is damaged or a different version. Try again.',
      );
      return false;
    }
    final target = p.join(p.dirname(path), model.file);
    await part.rename(target);
    _update(installed: {...state.installed, model});
    return true;
  }

  Future<void> delete(WhisperModel model) async {
    final dir = await _dir;
    for (final name in [model.file, '${model.file}.part']) {
      final file = File(p.join(dir.path, name));
      if (await file.exists()) await file.delete();
    }
    _update(
      downloading: state.downloading,
      received: state.received,
      verifying: state.verifying,
      installed: {...state.installed}..remove(model),
    );
  }

  static String _describe(Object e) => switch (e) {
    SocketException(:final message) ||
    HttpException(:final message) ||
    FileSystemException(:final message) => message,
    HandshakeException() => 'secure connection failed',
    _ => '$e',
  };
}

String _sha256Of(String path) {
  final digest = SHA256Digest();
  final file = File(path).openSync();
  try {
    final buffer = Uint8List(1 << 20);
    while (true) {
      final read = file.readIntoSync(buffer);
      if (read == 0) break;
      digest.update(buffer, 0, read);
    }
  } finally {
    file.closeSync();
  }
  final out = Uint8List(digest.digestSize);
  digest.doFinal(out, 0);
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
