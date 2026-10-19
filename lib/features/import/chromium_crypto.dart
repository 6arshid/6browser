import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import '../passwords/dpapi.dart';

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
          key = Uint8List.fromList(Dpapi.unprotect(raw));
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
      return utf8.decode(Dpapi.unprotect(bytes));
    } catch (_) {
      return '';
    }
  }
}
