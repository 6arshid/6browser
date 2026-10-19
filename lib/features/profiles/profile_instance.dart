import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// One window per profile. The process that opens a profile holds a lock on
/// a file in the profile's folder and listens on a loopback port; a later
/// launch of the same profile hands its command line to that window and
/// exits (CEF cannot run two processes on one profile folder anyway).
class ProfileInstance {
  ProfileInstance._(this._lock, this._server, this._token) {
    _server.listen(_serve, onError: (Object _) {});
  }

  final RandomAccessFile _lock;
  final ServerSocket _server;
  final String _token;

  /// Kept until someone listens, so an early hand-over is not lost.
  final _requests = StreamController<List<String>>();

  static File _lockFile(Directory dir) =>
      File(p.join(dir.path, 'instance.lock'));
  static File _infoFile(Directory dir) =>
      File(p.join(dir.path, 'instance.json'));

  /// Claims the profile in [dir]; null when another process has it.
  static Future<ProfileInstance?> acquire(Directory dir) async {
    await dir.create(recursive: true);
    // Append mode: never truncate a file another process has locked.
    final lock = await _lockFile(dir).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      return null;
    }
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    // Only processes that can read this user's profile folder learn the
    // token, so other users on the machine cannot open pages here.
    final random = Random.secure();
    final token = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    await _infoFile(dir).writeAsString(
      jsonEncode({'port': server.port, 'token': token}),
      flush: true,
    );
    return ProfileInstance._(lock, server, token);
  }

  /// Whether some process has the profile in [dir] open.
  static Future<bool> isRunning(Directory dir) async {
    final file = _lockFile(dir);
    if (!await file.exists()) return false;
    final lock = await file.open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      await lock.unlock();
      return false;
    } on FileSystemException {
      return true;
    } finally {
      await lock.close();
    }
  }

  /// Sends [args] to the window that has the profile in [dir]. False when
  /// it does not answer.
  static Future<bool> handOver(Directory dir, List<String> args) async {
    try {
      final info = jsonDecode(await _infoFile(dir).readAsString()) as Map;
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        info['port'] as int,
        timeout: const Duration(seconds: 3),
      );
      socket.writeln(jsonEncode({'token': info['token'], 'args': args}));
      await socket.flush();
      await socket.close();
      return true;
    } on Object {
      return false;
    }
  }

  /// Command lines handed over by later launches of this profile. Listen
  /// once.
  Stream<List<String>> get requests => _requests.stream;

  Future<void> _serve(Socket socket) async {
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      final message = jsonDecode(line) as Map;
      if (message['token'] == _token && !_requests.isClosed) {
        _requests.add([for (final a in message['args'] as List) '$a']);
      }
    } on Object {
      // Not a 6browser launch; ignore it.
    } finally {
      socket.destroy();
    }
  }

  Future<void> close() async {
    await _server.close();
    // Completes only once someone has listened.
    unawaited(_requests.close());
    await _lock.unlock();
    await _lock.close();
  }
}
