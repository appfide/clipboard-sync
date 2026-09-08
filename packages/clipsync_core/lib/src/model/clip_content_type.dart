import 'package:clipsync_core/clipsync_core.dart' show ClipItem;
import 'package:clipsync_core/src/model/clip_item.dart' show ClipItem;

/// Kind of payload carried by a [ClipItem].
///
/// The wire value (`text`, `url`, ...) is stored verbatim in every backend so
/// the enum can grow without a migration.
enum ClipContentType {
  /// Plain UTF-8 text.
  text('text'),

  /// A single URL (text that parses as an absolute URI).
  url('url'),

  /// HTML fragment; `content` holds the HTML, plain-text fallback is derived.
  html('html'),

  /// Image bytes, base64-encoded in `content` or referenced by `blobRef`.
  image('image'),

  /// Arbitrary file bytes, base64-encoded in `content` or referenced by `blobRef`.
  file('file');

  const ClipContentType(this.wire);

  /// Stable string persisted in the database.
  final String wire;

  /// Parses a wire value; unknown values fall back to [text].
  static ClipContentType fromWire(String? value) => ClipContentType.values
      .firstWhere((t) => t.wire == value, orElse: () => ClipContentType.text);

  /// Whether `content` is base64-encoded binary rather than human text.
  bool get isBinary => this == image || this == file;
}
