import 'package:clipsync_core/src/model/clip_item.dart';
import 'package:meta/meta.dart';

/// Membership state of a device in the sync group.
///
/// Enforcement is cooperative unless the backend's rules also read this
/// field (see `docs/devices.md`): a well-behaved client that sees itself as
/// [blocked] or [removed] stops syncing and forgets its credentials.
enum DeviceStatus {
  /// Syncing normally.
  active('active'),

  /// Temporarily excluded: other devices ignore its clips; it must stop
  /// syncing. Can be re-activated.
  blocked('blocked'),

  /// Permanently removed. The row stays as a tombstone so the device learns
  /// about its removal; *Forget* deletes the row afterwards.
  removed('removed');

  const DeviceStatus(this.wire);

  /// Value stored in the database.
  final String wire;

  /// Parses a wire value; unknown or missing values mean [active] so rows
  /// written by older app versions keep working.
  static DeviceStatus fromWire(String? v) => values.firstWhere(
    (s) => s.wire == v,
    orElse: () => DeviceStatus.active,
  );
}

/// What a device is allowed to do with the shared history.
enum DeviceRole {
  /// Sends and receives clips.
  full('full'),

  /// Only pushes its own clips; never pulls history (a guest machine).
  sendOnly('send_only'),

  /// Only receives clips; never pushes what it copies (a display / kiosk).
  receiveOnly('receive_only');

  const DeviceRole(this.wire);

  /// Value stored in the database.
  final String wire;

  /// Whether this role pulls other devices' clips.
  bool get canReceive => this != DeviceRole.sendOnly;

  /// Whether this role pushes its own clips.
  bool get canSend => this != DeviceRole.receiveOnly;

  /// Human-readable label.
  String get label => switch (this) {
    DeviceRole.full => 'Send & receive',
    DeviceRole.sendOnly => 'Send only',
    DeviceRole.receiveOnly => 'Receive only',
  };

  /// Parses a wire value; unknown or missing values mean [full].
  static DeviceRole fromWire(String? v) =>
      values.firstWhere((r) => r.wire == v, orElse: () => DeviceRole.full);
}

/// A device participating in a sync group.
///
/// Two kinds of fields live on a device row:
///
/// * **Presence** (`name`, `platform`, `last_seen`, `app_version`) — written
///   by the device itself on every heartbeat via `SyncBackend.registerDevice`.
/// * **Membership** (`status`, `role`, `expires_at`, `paired_by`) — written by
///   whichever device manages the group via `SyncBackend.updateDevice`. A
///   heartbeat must never overwrite these.
@immutable
class Device {
  /// Creates a device record.
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeen,
    this.status = DeviceStatus.active,
    this.role = DeviceRole.full,
    this.expiresAt,
    this.pairedBy,
    this.appVersion,
  });

  /// Parses the canonical map produced by [toMap]. Missing membership fields
  /// take their defaults so rows from older schemas still parse.
  factory Device.fromMap(Map<String, Object?> map) => Device(
    id: map['id']! as String,
    name: (map['name'] ?? '') as String,
    platform: (map['platform'] ?? '') as String,
    lastSeen:
        ClipItem.parseTimestamp(map['last_seen']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    status: DeviceStatus.fromWire(map['status'] as String?),
    role: DeviceRole.fromWire(map['role'] as String?),
    expiresAt: ClipItem.parseTimestamp(map['expires_at']),
    pairedBy: _nullIfEmpty(map['paired_by']),
    appVersion: _nullIfEmpty(map['app_version']),
  );

  /// Stable UUID generated on first launch (or adopted from a pairing code)
  /// and kept in app preferences.
  final String id;

  /// User-visible name (hostname / model by default).
  final String name;

  /// `macos`, `windows`, `linux`, `android`, `ios`.
  final String platform;

  /// Last heartbeat (UTC).
  final DateTime lastSeen;

  /// Membership state.
  final DeviceStatus status;

  /// Permissions.
  final DeviceRole role;

  /// When membership ends (UTC), or `null` for permanent access.
  final DateTime? expiresAt;

  /// Id of the device that issued the pairing code, if any.
  final String? pairedBy;

  /// App version the device last reported.
  final String? appVersion;

  /// Whether [expiresAt] has passed.
  bool isExpired(DateTime now) {
    final e = expiresAt;
    return e != null && !now.toUtc().isBefore(e);
  }

  /// Whether the device may sync at [now]: active and not expired.
  bool canSync(DateTime now) =>
      status == DeviceStatus.active && !isExpired(now);

  /// Whether the device heartbeat is recent enough to count as online.
  bool isOnline(DateTime now, {Duration within = const Duration(minutes: 3)}) =>
      now.toUtc().difference(lastSeen) <= within;

  /// Whether the device has never sent a heartbeat (row pre-created by a
  /// pairing code that has not been used yet).
  bool get isPending => lastSeen.millisecondsSinceEpoch == 0;

  /// Keys of the presence fields (everything a heartbeat may write).
  static const Set<String> presenceKeys = {
    'id',
    'name',
    'platform',
    'last_seen',
    'app_version',
  };

  /// Keys of the membership fields (written only by `updateDevice`).
  static const Set<String> membershipKeys = {
    'status',
    'role',
    'expires_at',
    'paired_by',
  };

  /// Canonical document shape shared by all backends.
  Map<String, Object?> toMap() => <String, Object?>{
    ...presenceMap(),
    'status': status.wire,
    'role': role.wire,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'paired_by': pairedBy,
  };

  /// Only the presence fields — what a heartbeat is allowed to write.
  Map<String, Object?> presenceMap() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform,
    'last_seen': lastSeen.toUtc().toIso8601String(),
    'app_version': appVersion,
  };

  /// Copy with fields replaced. `clearExpiresAt` removes the expiry.
  Device copyWith({
    String? name,
    String? platform,
    DateTime? lastSeen,
    DeviceStatus? status,
    DeviceRole? role,
    DateTime? expiresAt,
    String? pairedBy,
    String? appVersion,
    bool clearExpiresAt = false,
  }) => Device(
    id: id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    lastSeen: lastSeen ?? this.lastSeen,
    status: status ?? this.status,
    role: role ?? this.role,
    expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
    pairedBy: pairedBy ?? this.pairedBy,
    appVersion: appVersion ?? this.appVersion,
  );

  /// Returns a copy with presence fields taken from [presence] and
  /// membership fields kept — how backends merge a heartbeat into an
  /// existing row.
  Device withPresence(Device presence) => copyWith(
    name: presence.name,
    platform: presence.platform,
    lastSeen: presence.lastSeen,
    appVersion: presence.appVersion,
  );

  static String? _nullIfEmpty(Object? v) =>
      v is String && v.isNotEmpty ? v : null;

  @override
  bool operator ==(Object other) => other is Device && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Device($name/$platform, ${status.wire}, ${role.wire})';
}
