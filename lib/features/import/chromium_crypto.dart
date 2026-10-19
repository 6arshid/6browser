import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

/// Decrypts Chromium "Login Data" password blobs on Windows.
///
/// Modern Chromium (v80+) wraps each password with AES-256-GCM using a per-user
/// master key; that key lives in `Local State` encrypted with Windows DPAPI.
/// Older blobs are DPAPI-encrypted directly. Decryption only works for the same
/// Windows user on the same machine — exactly the migration case we support.
class ChromiumDecryptor {
  ChromiumDecryptor(this._masterKey);

  /// 32-byte AES key, or null when no `os_crypt` key was present (very old
  /// profiles that only use raw DPAPI).
  final Uint8List? _masterKey;

  /// Loads the AES master key from `<userData>/Local State`. Returns a
  /// decryptor even when the key is absent, so legacy blobs still work.
  static ChromiumDecryptor forUserData(String userDataPath) {
    final file = File(p.join(userDataPath, 'Local State'));
    Uint8List? key;
    if (file.existsSync()) {
      final data = jsonDecode(file.readAsStringSync());
      final encoded = (data is Map ? data['os_crypt'] : null) is Map
          ? ((data['os_crypt'] as Map)['encrypted_key'] as String?)
          : null;
      if (encoded != null) {
        var raw = base64.decode(encoded);
        // Strip the "DPAPI" prefix, then unprotect to get the 32-byte key.
        if (raw.length > 5) {
          raw = raw.sublist(5);
          key = Uint8List.fromList(_dpapiUnprotect(raw));
        }
      }
    }
    return ChromiumDecryptor(key);
  }

  /// Decrypts a single password blob to clear text. Returns an empty string if
  /// the blob cannot be decrypted (so one bad row never aborts the import).
  String decrypt(List<int> blob) {
    if (blob.isEmpty) return '';
    final bytes = Uint8List.fromList(blob);
    final prefix = bytes.length >= 3
        ? String.fromCharCodes(bytes.sublist(0, 3))
        : '';
    try {
      if ((prefix == 'v10' || prefix == 'v11') && _masterKey != null) {
        final nonce = bytes.sublist(3, 15);
        final payload = bytes.sublist(15); // ciphertext + 16-byte GCM tag
        final gcm = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(
              KeyParameter(_masterKey),
              128,
              Uint8List.fromList(nonce),
              Uint8List(0),
            ),
          );
        return utf8.decode(gcm.process(Uint8List.fromList(payload)));
      }
      // Legacy: the blob is DPAPI-encrypted directly.
      return utf8.decode(_dpapiUnprotect(bytes));
    } catch (_) {
      return '';
    }
  }
}

// ---- Windows DPAPI (CryptUnprotectData) via FFI ----

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptUnprotectC = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptUnprotectDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Pointer<Utf16>> ppszDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeC = Pointer<Void> Function(Pointer<Void> hMem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

final _crypt32 = DynamicLibrary.open('crypt32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _cryptUnprotect = _crypt32
    .lookupFunction<_CryptUnprotectC, _CryptUnprotectDart>(
      'CryptUnprotectData',
    );
final _localFree = _kernel32.lookupFunction<_LocalFreeC, _LocalFreeDart>(
  'LocalFree',
);

Uint8List _dpapiUnprotect(List<int> input) {
  final inPtr = calloc<_DataBlob>();
  final outPtr = calloc<_DataBlob>();
  final buffer = calloc<Uint8>(input.length);
  try {
    buffer.asTypedList(input.length).setAll(0, input);
    inPtr.ref
      ..cbData = input.length
      ..pbData = buffer;

    final ok = _cryptUnprotect(
      inPtr,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      0,
      outPtr,
    );
    if (ok == 0) {
      throw const _DpapiException();
    }
    final out = Uint8List.fromList(
      outPtr.ref.pbData.asTypedList(outPtr.ref.cbData),
    );
    _localFree(outPtr.ref.pbData.cast());
    return out;
  } finally {
    calloc.free(buffer);
    calloc.free(inPtr);
    calloc.free(outPtr);
  }
}

class _DpapiException implements Exception {
  const _DpapiException();
  @override
  String toString() => 'CryptUnprotectData failed';
}
