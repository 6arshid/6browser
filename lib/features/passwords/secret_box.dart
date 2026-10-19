import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth_platform_interface/types/auth_exception.dart';
import 'package:local_auth_windows/local_auth_windows.dart';

import 'dpapi.dart';

/// Encrypts saved passwords with a key only the signed-in user of this
/// device can use: Windows DPAPI, or the Android Keystore.
abstract class SecretBox {
  /// False where 6browser cannot store passwords safely yet.
  bool get isAvailable;

  Future<Uint8List> seal(String secret);
  Future<String> open(Uint8List sealed);
}

class _WindowsSecretBox implements SecretBox {
  // Ties the data to 6browser: other apps of the same user that call DPAPI
  // without it cannot decrypt the passwords.
  static final _entropy = utf8.encode('6browser saved passwords');

  @override
  bool get isAvailable => true;
  @override
  Future<Uint8List> seal(String secret) async =>
      Dpapi.protect(utf8.encode(secret), entropy: _entropy);
  @override
  Future<String> open(Uint8List sealed) async =>
      utf8.decode(Dpapi.unprotect(sealed, entropy: _entropy));
}

/// AES-GCM with a key that never leaves the Android Keystore (MainActivity).
class _AndroidSecretBox implements SecretBox {
  static const _app = MethodChannel('6browser/app');

  @override
  bool get isAvailable => true;
  @override
  Future<Uint8List> seal(String secret) async =>
      (await _app.invokeMethod<Uint8List>('sealSecret', secret))!;
  @override
  Future<String> open(Uint8List sealed) async =>
      (await _app.invokeMethod<String>('openSecret', sealed))!;
}

class _UnavailableSecretBox implements SecretBox {
  const _UnavailableSecretBox();

  @override
  bool get isAvailable => false;
  @override
  Future<Uint8List> seal(String secret) =>
      throw UnsupportedError('Saving passwords is not available here');
  @override
  Future<String> open(Uint8List sealed) =>
      throw UnsupportedError('Saving passwords is not available here');
}

/// Overridden in tests.
final secretBoxProvider = Provider<SecretBox>(
  (ref) => Platform.isWindows
      ? _WindowsSecretBox()
      : Platform.isAndroid
      ? _AndroidSecretBox()
      : const _UnavailableSecretBox(),
);

/// Asks the operating system to confirm it is the device's user (Windows
/// Hello, or the Android screen lock) before passwords are shown, copied or
/// exported. A confirmation lasts a minute, as in Chrome. Devices without a
/// PIN, fingerprint or screen lock are not asked.
class UserVerifier {
  DateTime? _until;

  Future<bool> verify(String reason) async {
    final until = _until;
    if (until != null && DateTime.now().isBefore(until)) return true;
    final ok = await _ask(reason);
    if (ok) _until = DateTime.now().add(const Duration(minutes: 1));
    return ok;
  }

  Future<bool> _ask(String reason) async {
    if (Platform.isWindows) {
      final auth = LocalAuthWindows();
      try {
        if (!await auth.isDeviceSupported()) return true;
        return await auth.authenticate(
          localizedReason: reason,
          authMessages: const [],
        );
      } on LocalAuthException catch (e) {
        return e.code == LocalAuthExceptionCode.noBiometricsEnrolled ||
            e.code == LocalAuthExceptionCode.noBiometricHardware;
      }
    }
    if (Platform.isAndroid) {
      return await const MethodChannel('6browser/app')
              .invokeMethod<bool>('verifyUser', reason) ??
          false;
    }
    return true;
  }
}

/// Overridden in tests.
final userVerifierProvider = Provider<UserVerifier>((ref) => UserVerifier());
