import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Chrome's extension id for a public key (DER SubjectPublicKeyInfo): the
/// first 16 bytes of its SHA-256, one letter a-p per hex digit.
String extensionIdForKey(Uint8List publicKey) =>
    _idLetters(SHA256Digest().process(publicKey).take(16).toList());

/// The developer's public key from a CRX2/CRX3 package, as the base64 value
/// of a manifest "key". Loading the unpacked files with this key keeps the
/// extension's Web Store id. Null for plain ZIP data, or when no key in the
/// package gives [expectedId]. Without [expectedId], a CRX3 package's own id
/// (its signed header) picks the key.
String? crxPublicKey(Uint8List bytes, {String? expectedId}) {
  if (bytes.length < 16 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'Cr24') {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  final keys = <Uint8List>[];
  switch (data.getUint32(4, Endian.little)) {
    case 2:
      final length = data.getUint32(8, Endian.little);
      if (16 + length > bytes.length) return null;
      keys.add(Uint8List.sublistView(bytes, 16, 16 + length));
    case 3:
      final length = data.getUint32(8, Endian.little);
      if (12 + length > bytes.length) return null;
      final header = Uint8List.sublistView(bytes, 12, 12 + length);
      // CrxFileHeader: sha256_with_rsa = 2, sha256_with_ecdsa = 3, each an
      // AsymmetricKeyProof whose public_key is field 1; signed_header_data =
      // 10000, a SignedData whose crx_id (16 bytes) is field 1.
      for (final (field, value) in _protoFields(header)) {
        if (field == 2 || field == 3) {
          for (final (f, key) in _protoFields(value)) {
            if (f == 1) keys.add(key);
          }
        } else if (field == 10000 && expectedId == null) {
          for (final (f, crxId) in _protoFields(value)) {
            if (f == 1 && crxId.length == 16) expectedId = _idLetters(crxId);
          }
        }
      }
    default:
      return null;
  }
  for (final key in keys) {
    if (expectedId == null || extensionIdForKey(key) == expectedId) {
      return base64.encode(key);
    }
  }
  return null;
}

String _idLetters(List<int> bytes) {
  final id = StringBuffer();
  for (final b in bytes) {
    id
      ..writeCharCode(0x61 + (b >> 4))
      ..writeCharCode(0x61 + (b & 0xf));
  }
  return id.toString();
}

/// The length-delimited fields of a protobuf message, as (field, bytes).
/// Other wire types are skipped; damaged data ends the list.
List<(int, Uint8List)> _protoFields(Uint8List message) {
  final fields = <(int, Uint8List)>[];
  var i = 0;
  int? varint() {
    var result = 0, shift = 0;
    while (i < message.length && shift < 64) {
      final b = message[i++];
      result |= (b & 0x7f) << shift;
      if (b < 0x80) return result;
      shift += 7;
    }
    return null;
  }

  while (i < message.length) {
    final tag = varint();
    if (tag == null) break;
    switch (tag & 7) {
      case 0:
        if (varint() == null) return fields;
      case 1:
        i += 8;
      case 2:
        final length = varint();
        if (length == null || length < 0 || i + length > message.length) {
          return fields;
        }
        fields.add((tag >> 3, Uint8List.sublistView(message, i, i + length)));
        i += length;
      case 5:
        i += 4;
      default:
        return fields;
    }
  }
  return fields;
}
