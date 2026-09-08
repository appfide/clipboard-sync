import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256 hex digest of UTF-8 [text].
String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

/// SHA-256 hex digest of raw [bytes].
String sha256HexBytes(Uint8List bytes) => sha256.convert(bytes).toString();
