import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Windows DPAPI: data encrypted with the signed-in Windows user's key, so
/// only that user on this computer can decrypt it.
class Dpapi {
  Dpapi._();

  /// CRYPTPROTECT_UI_FORBIDDEN: fail instead of showing a prompt.
  static const _noUi = 0x1;

  static Uint8List protect(List<int> data, {List<int>? entropy}) =>
      _run(_protect, data, entropy);

  /// Throws [DpapiException] when the data was not encrypted by this
  /// Windows user (or with other [entropy]).
  static Uint8List unprotect(List<int> data, {List<int>? entropy}) =>
      _run(_unprotect, data, entropy);

  static Uint8List _run(_CryptDart call, List<int> data, List<int>? entropy) {
    final input = calloc<_DataBlob>();
    final extra = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final inBytes = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final extraBytes = calloc<Uint8>(
      entropy == null || entropy.isEmpty ? 1 : entropy.length,
    );
    try {
      inBytes.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = inBytes;
      if (entropy != null) {
        extraBytes.asTypedList(entropy.length).setAll(0, entropy);
        extra.ref
          ..cbData = entropy.length
          ..pbData = extraBytes;
      }
      final ok = call(
        input,
        nullptr,
        entropy == null ? nullptr : extra,
        nullptr,
        nullptr,
        _noUi,
        output,
      );
      if (ok == 0) throw const DpapiException();
      final out = Uint8List.fromList(
        output.ref.pbData.asTypedList(output.ref.cbData),
      );
      _localFree(output.ref.pbData.cast());
      return out;
    } finally {
      calloc
        ..free(inBytes)
        ..free(extraBytes)
        ..free(input)
        ..free(extra)
        ..free(output);
    }
  }
}

class DpapiException implements Exception {
  const DpapiException();

  @override
  String toString() => 'Windows could not decrypt or encrypt the data';
}

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

// CryptProtectData and CryptUnprotectData have the same shape (the second
// argument is the description in or out).
typedef _CryptC = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);
typedef _CryptDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Void> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);

final _crypt32 = DynamicLibrary.open('crypt32.dll');
final _protect = _crypt32.lookupFunction<_CryptC, _CryptDart>(
  'CryptProtectData',
);
final _unprotect = _crypt32.lookupFunction<_CryptC, _CryptDart>(
  'CryptUnprotectData',
);
final _localFree = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');
