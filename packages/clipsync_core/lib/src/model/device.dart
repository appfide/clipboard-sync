import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:meta/meta.dart';

/// A device participating in a sync group.
@immutable
class Device {
  /// Creates a device record.
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeen,
  });

  /// Parses the canonical map produced by [toMap].
  factory Device.fromMap(Map<String, Object?> map) => Device(
    id: map['id']! as String,
    name: (map['name'] ?? '') as String,
    platform: (map['platform'] ?? '') as String,
    lastSeen:
        ClipItem.parseTimestamp(map['last_seen']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  /// Stable UUID generated on first launch and kept in secure storage.
  final String id;

  /// User-visible name (hostname / model by default).
  final String name;

  /// `macos`, `windows`, `linux`, `android`, `ios`.
  final String platform;

  /// Last heartbeat (UTC).
  final DateTime lastSeen;

  /// Canonical document shape shared by all backends.
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform,
    'last_seen': lastSeen.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) => other is Device && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Device($name/$platform)';
}
