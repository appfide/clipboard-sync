import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clipboard_sync/core/build_info.dart';
import 'package:clipboard_sync/core/logging.dart';
import 'package:clipboard_sync/core/platform_info.dart';
import 'package:clipboard_sync/data/settings/app_settings.dart';
import 'package:clipboard_sync/platform/clipboard_service.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Owns the [SyncEngine], the connected backend and the clipboard capture
/// pipeline. Rebuilds when sync-affecting settings change.
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

/// Live device list of the current sync group (empty in local-only mode).
final deviceListProvider = StreamProvider<List<Device>>(
  (ref) => ref.watch(syncControllerProvider.notifier).devices,
);

/// Why this device lost access to its sync group. Set once by the
/// controller when the engine reports [SyncPhase.revoked]; the UI shows it
/// and clears it.
class RevocationNotice {
  /// Creates a notice.
  const RevocationNotice({required this.reason, required this.backendName});

  /// `blocked`, `removed` or `expired`.
  final String reason;

  /// Display name of the backend the device was removed from.
  final String backendName;

  /// User-facing headline.
  String get title => switch (reason) {
    'blocked' => 'This device was blocked',
    'expired' => 'This device’s access has expired',
    _ => 'This device was removed',
  };

  /// User-facing detail.
  String get detail =>
      'Another device in your $backendName sync group ${switch (reason) {
        'blocked' => 'blocked this device',
        'expired' => 'gave this device temporary access, which has now ended',
        _ => 'removed this device',
      }}. The database credentials and passphrase were deleted from this device; '
      'your local history is still here. To rejoin, pair again from a device that still has access.';
}

/// An admin key seen on the group that this device has not pinned yet.
final pendingTrustProvider =
    NotifierProvider<PendingTrustNotifier, PendingTrust?>(
      PendingTrustNotifier.new,
    );

/// Holds the pending [PendingTrust].
class PendingTrustNotifier extends Notifier<PendingTrust?> {
  @override
  PendingTrust? build() => null;

  /// Pending request.
  PendingTrust? get request => state;

  /// Sets or clears the request.
  set request(PendingTrust? value) => state = value;
}

/// Pending revocation notice, or `null`.
final revocationProvider =
    NotifierProvider<RevocationNotifier, RevocationNotice?>(
      RevocationNotifier.new,
    );

/// Holds the pending [RevocationNotice].
class RevocationNotifier extends Notifier<RevocationNotice?> {
  @override
  RevocationNotice? build() => null;

  /// Pending notice.
  RevocationNotice? get notice => state;

  /// Sets or clears the notice.
  set notice(RevocationNotice? value) => state = value;
}

/// A generated pairing code and its PIN, shown by the host.
class PairingSession {
  /// Creates a session.
  const PairingSession({
    required this.code,
    required this.pin,
    required this.deviceId,
    required this.validUntil,
    required this.passphraseIncluded,
    required this.encryption,
    required this.grantsAdmin,
  });

  /// Sealed code (QR / text).
  final String code;

  /// 8-digit PIN the joiner must type.
  final String pin;

  /// Device id pre-created for the joiner.
  final String deviceId;

  /// After this instant the joiner refuses the code.
  final DateTime validUntil;

  /// Whether the E2E passphrase travelled inside the code.
  final bool passphraseIncluded;

  /// Whether the group encrypts (joiner must type the passphrase when it
  /// was not included).
  final bool encryption;

  /// Whether the code also carries the admin key.
  final bool grantsAdmin;
}

/// Sync lifecycle notifier; state is the engine status.
class SyncController extends Notifier<SyncStatus> {
  SyncEngine? _engine;
  SyncBackend? _backend;
  ClipboardService? _clipboard;
  StreamSubscription<SyncStatus>? _statusSub;
  StreamSubscription<List<ClipItem>>? _incomingSub;
  StreamSubscription<List<Device>>? _devicesSub;
  StreamSubscription<PendingTrust>? _trustSub;
  StreamSubscription<ClipItem>? _captureSub;
  Timer? _retention;
  final _devicesOut = StreamController<List<Device>>.broadcast();
  DeviceKeys? _identity;
  AdminKey? _adminKey;
  String? _trustedAdminPub;

  @override
  SyncStatus build() {
    ref
      ..listen<AppSettings>(settingsProvider, (prev, next) {
        if (prev == null) return;
        final c = _clipboard;
        if (c != null) {
          c
            ..deviceId = next.deviceId
            ..deviceName = next.deviceName
            ..captureImages = next.captureImages
            ..maxInlineBytes = next.maxInlineKb * 1024
            ..skipSensitive = next.skipSensitive
            ..skipSecretLike = next.skipSecretLike
            ..paused = next.capturePaused;
        }
        if (prev.capturePaused != next.capturePaused) {
          unawaited(
            ref
                .read(desktopShellProvider)
                ?.setPaused(paused: next.capturePaused),
          );
        }
        // Only a running engine needs restarting; before start() the seeded
        // secrets simply become part of the initial configuration.
        if (_engine != null && AppSettings.syncAffecting(prev, next)) {
          unawaited(restart());
        }
      })
      ..onDispose(() => unawaited(_teardown()));
    return const SyncStatus.stopped();
  }

  /// Backend currently connected (for settings screens).
  SyncBackend? get backend => _backend;

  /// Clipboard service (for share/notification entry points).
  ClipboardService? get clipboard => _clipboard;

  /// Device list snapshots from the running engine.
  Stream<List<Device>> get devices => _devicesOut.stream;

  /// Last known device list.
  List<Device> get knownDevices => _engine?.knownDevices ?? const [];

  /// Ids of devices whose membership verifies (signed group) or is active
  /// (legacy group).
  Set<String> get trustedDeviceIds =>
      _engine?.trustedDevices.keys.toSet() ?? const {};

  /// Whether a remote group is connected, so devices can be managed and
  /// pairing codes generated.
  bool get canManageDevices =>
      _engine != null && ref.read(settingsProvider).syncsRemotely;

  /// Whether this device holds the group's admin key.
  bool get isAdmin => _adminKey != null;

  /// Whether the group has a pinned admin key (signed membership).
  bool get isSignedGroup => _trustedAdminPub != null;

  /// Pinned admin public key (base64), or `null`.
  String? get adminPublicKey => _trustedAdminPub;

  /// Fingerprint of the pinned admin key, or `null`.
  String? get adminFingerprint =>
      _trustedAdminPub == null ? null : keyFingerprint(_trustedAdminPub!);

  /// Whether this device may change membership: legacy group, or admin.
  bool get canEditMembership => canManageDevices && (!isSignedGroup || isAdmin);

  /// This device's signing-key fingerprint, or `null` before first start.
  String? get deviceFingerprint => _identity?.fingerprint;

  /// Starts sync, then clipboard capture, from current settings.
  Future<void> start() async {
    final s = ref.read(settingsProvider);
    // Engine first: a clipboard permission prompt on mobile must never
    // delay connecting to the backend.
    await _startEngine(s);
    if (_clipboard == null) {
      final c = ClipboardService(
        deviceId: s.deviceId,
        deviceName: s.deviceName,
        captureImages: s.captureImages,
        maxInlineBytes: s.maxInlineKb * 1024,
        paused: s.capturePaused,
        skipSensitive: s.skipSensitive,
        skipSecretLike: s.skipSecretLike,
      );
      _captureSub = c.captured.listen(_onCaptured);
      _clipboard = c;
      await c.start();
    }
  }

  Future<void> _onCaptured(ClipItem item) async {
    final store = ref.read(localStoreProvider);
    // A receive-only device keeps what it copies to itself.
    final localOnly = !state.role.canSend;
    final inserted = await store.capture(item, localOnly: localOnly);
    if (inserted) {
      log.i(
        'captured ${item.type.wire} ${item.sizeBytes}B'
        '${localOnly ? ' (local only)' : ''}',
      );
      if (!localOnly) await _engine?.syncNow();
    }
  }

  /// Stops and starts the engine (settings changed).
  Future<void> restart() async {
    await _stopEngine();
    await _startEngine(ref.read(settingsProvider));
  }

  /// Push + pull now.
  Future<void> syncNow() async => _engine?.syncNow();

  /// Reads the clipboard immediately (mobile entry points).
  Future<void> captureNow() async => _clipboard?.checkNow();

  /// Checks clipboard access for the Permissions section.
  Future<ClipboardProbe> probeClipboard() async =>
      _clipboard?.probe() ??
      const ClipboardProbe(
        ClipboardAccess.blocked,
        'Capture service not running.',
      );

  /// Writes [item] to the clipboard.
  Future<void> copyToClipboard(ClipItem item) async => _clipboard?.write(item);

  /// Writes [text] to the clipboard without recording it in history.
  Future<void> copyTextUnrecorded(String text) async =>
      _clipboard?.writeText(text);

  /// Deletes an item locally and (via outbox) remotely.
  Future<void> delete(String id) async {
    await ref.read(localStoreProvider).delete(id, DateTime.now().toUtc());
    await _engine?.syncNow();
  }

  /// Queues a copy of [item] addressed to [deviceId] only.
  Future<void> sendToDevice(ClipItem item, String deviceId) async {
    final s = ref.read(settingsProvider);
    final copy = ClipItem.create(
      id: const Uuid().v4(),
      deviceId: s.deviceId,
      deviceName: s.deviceName,
      type: item.type,
      content: item.content,
      contentHash: item.contentHash,
      sizeBytes: item.sizeBytes,
      now: DateTime.now().toUtc(),
      blobRef: item.blobRef,
      targetDeviceId: deviceId,
    );
    await ref.read(localStoreProvider).enqueue(copy);
    await _engine?.syncNow();
  }

  /// Tests a backend configuration without touching the running engine.
  Future<(ConnectionCheck, SchemaCheck?)> probe(BackendConfig config) async {
    final b = ref.read(backendRegistryProvider).create(config.backendId);
    try {
      await b.connect(config);
      final conn = await b.testConnection();
      if (!conn.ok) return (conn, null);
      final schema = await b.verifySchema();
      return (conn, schema);
    } on BackendException catch (e) {
      return (ConnectionCheck.failure(e.message), null);
    } catch (e) {
      return (ConnectionCheck.failure(redactSecrets(e.toString())), null);
    } finally {
      await b.dispose();
    }
  }

  /// Runs local + remote retention.
  Future<void> runRetention() async {
    final days = ref.read(settingsProvider).retentionDays;
    if (days <= 0) return;
    final before = DateTime.now().toUtc().subtract(Duration(days: days));
    try {
      final local = await ref.read(localStoreProvider).purgeBefore(before);
      final remote = await _backend?.purgeBefore(before) ?? 0;
      log.i(
        'retention: purged $local local, $remote remote (older than $days d)',
      );
    } catch (e) {
      log.w('retention failed', error: e);
    }
  }

  // --- Device management ---------------------------------------------------

  SyncEngine get _managed =>
      _engine ?? (throw StateError('Sync is not running'));

  /// Re-reads the device list.
  Future<List<Device>> refreshDevices() => _managed.refreshDevices();

  /// See [SyncEngine.blockDevice].
  Future<void> blockDevice(String id) => _managed.blockDevice(id);

  /// See [SyncEngine.unblockDevice].
  Future<void> unblockDevice(String id) => _managed.unblockDevice(id);

  /// See [SyncEngine.removeDevice].
  Future<void> removeDevice(String id) => _managed.removeDevice(id);

  /// See [SyncEngine.forgetDevice].
  Future<void> forgetDevice(String id) => _managed.forgetDevice(id);

  /// See [SyncEngine.setDeviceRole].
  Future<void> setDeviceRole(String id, DeviceRole role) =>
      _managed.setDeviceRole(id, role);

  /// See [SyncEngine.setDeviceExpiry].
  Future<void> setDeviceExpiry(String id, DateTime? expiresAt) =>
      _managed.setDeviceExpiry(id, expiresAt);

  // --- Pairing -------------------------------------------------------------

  /// Pre-registers a device row and seals the current backend settings into
  /// a pairing code. The row stays pending until the joiner's first
  /// heartbeat; cancel it with [forgetDevice] if the code goes unused.
  Future<PairingSession> createPairing({
    required DeviceRole role,
    DateTime? expiresAt,
    bool includePassphrase = false,
    bool grantAdmin = false,
    Duration validity = PairingCodec.defaultValidity,
  }) async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) {
      throw StateError('Local-only mode has no database to share');
    }
    if (isSignedGroup && !isAdmin) {
      throw StateError('Only the admin device can add devices to this group');
    }
    final engine = _managed;
    final id = const Uuid().v4();
    final pin = PairingCodec.generatePin();
    final now = DateTime.now().toUtc();
    // The host generates the new device's identity so it can sign its
    // public keys (and seal the passphrase to it) before it ever connects.
    final joinerKeys = await DeviceKeys.generate();
    String? passphrase;
    if (includePassphrase && s.encryptionEnabled) {
      passphrase = await ref.read(settingsRepositoryProvider).loadPassphrase();
    }
    await engine.inviteDevice(
      id: id,
      role: role,
      expiresAt: expiresAt,
      signPub: joinerKeys.signPub,
      boxPub: joinerKeys.boxPub,
      admin: grantAdmin && isAdmin,
      passphrase: passphrase,
    );
    final adminPub = _trustedAdminPub ?? _adminKey?.publicKey;
    final payload = PairingPayload(
      backendId: s.backendId,
      values: Map.of(s.backendValues),
      deviceId: id,
      issuedAt: now,
      validUntil: now.add(validity),
      hostDeviceId: s.deviceId,
      hostDeviceName: s.deviceName,
      deviceKeys: await joinerKeys.encode(),
      adminPub: adminPub,
      adminKey: grantAdmin && isAdmin ? await _adminKey!.encode() : null,
      encryption: s.encryptionEnabled,
      passphraseDelivered: passphrase != null,
      role: role,
      expiresAt: expiresAt,
    );
    final code = await PairingCodec.seal(payload, pin);
    log.i('pairing code issued for $id (${role.wire})');
    return PairingSession(
      code: code,
      pin: pin,
      deviceId: id,
      validUntil: payload.validUntil,
      passphraseIncluded: passphrase != null,
      encryption: s.encryptionEnabled,
      grantsAdmin: payload.adminKey != null,
    );
  }

  /// Adopts everything in [payload]: device id, backend settings and
  /// (optionally) the passphrase. The settings listener restarts the engine
  /// against the new group.
  Future<void> joinFromPairing(
    PairingPayload payload, {
    String? passphrase,
  }) async {
    final registry = ref.read(backendRegistryProvider);
    if (registry.descriptor(payload.backendId) == null) {
      throw StateError(
        'This code is for a database type this build does not support (${payload.backendId}).',
      );
    }
    final repo = ref.read(settingsRepositoryProvider);
    if (payload.needsPassphrase && (passphrase == null || passphrase.isEmpty)) {
      throw StateError('This group uses encryption; a passphrase is required.');
    }
    final scope = AppSettings(
      deviceId: payload.deviceId,
      deviceName: '',
      backendId: payload.backendId,
      backendValues: payload.values,
    ).backendScope;
    await repo.saveRegisteredScope(null);
    await ref.read(localStoreProvider).resetCursor();
    // Identity chosen by the host; keys arrive only through the PIN-sealed
    // code, never through the database.
    final keys = payload.deviceKeys;
    if (keys != null) {
      await repo.saveDeviceKeys(keys);
      _identity = await DeviceKeys.decode(keys);
    }
    await repo.clearGroupTrust(scope);
    await repo.saveTrustedAdminPub(scope, payload.adminPub);
    await repo.saveAdminKey(scope, payload.adminKey);
    // Passphrase: either sealed to us in our device row (arrives on first
    // check-in) or typed now.
    await repo.saveKeyring(
      payload.encryption && !payload.passphraseDelivered
          ? {1: passphrase!}
          : {},
    );
    await ref
        .read(settingsProvider.notifier)
        .update(
          (x) => x.copyWith(
            deviceId: payload.deviceId,
            backendId: payload.backendId,
            backendValues: Map.of(payload.values),
            encryptionEnabled: payload.encryption,
            onboarded: true,
          ),
        );
    log.i('joined ${payload.backendId} group from ${payload.hostDeviceName}');
  }

  // --- Group security --------------------------------------------------------

  /// Turns the current (legacy) group into a signed one managed by this
  /// device: generates the admin key, pins it, signs every active row.
  Future<void> secureGroup() async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) throw StateError('No sync group');
    if (isSignedGroup) throw StateError('Group is already secured');
    final repo = ref.read(settingsRepositoryProvider);
    final key = await AdminKey.generate();
    await repo.saveAdminKey(s.backendScope, await key.encode());
    await repo.saveTrustedAdminPub(s.backendScope, key.publicKey);
    await restart();
    await _managed.secureGroup();
    log.i('group secured; admin key ${key.fingerprint}');
  }

  /// Pins [adminPub] for the current group after the user compared the
  /// fingerprint with the admin device.
  Future<void> trustAdmin(String adminPub) async {
    final s = ref.read(settingsProvider);
    await ref
        .read(settingsRepositoryProvider)
        .saveTrustedAdminPub(s.backendScope, adminPub);
    ref.read(pendingTrustProvider.notifier).request = null;
    await restart();
  }

  /// Issues a fresh random passphrase to every verified active device.
  /// Returns the new version.
  Future<int> rotatePassphrase() async {
    final s = ref.read(settingsProvider);
    if (!s.encryptionEnabled) throw StateError('Encryption is off');
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final passphrase = base64UrlEncode(bytes);
    await _managed.rotatePassphrase(passphrase);
    return _managed.status.keyVersion;
  }

  // --- Internals -----------------------------------------------------------

  Future<void> _startEngine(AppSettings s) async {
    // Never run two engines against the same store.
    if (_engine != null || _backend != null) await _stopEngine();
    final registry = ref.read(backendRegistryProvider);
    final store = ref.read(localStoreProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final descriptor = registry.descriptor(s.backendId);
    if (descriptor == null) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: 'Unknown backend ${s.backendId}',
      );
      return;
    }
    final errors = s.backendConfig.validate(descriptor);
    if (errors.isNotEmpty) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: 'Backend settings incomplete: ${errors.values.first}',
        authFailed: true,
      );
      return;
    }

    final scope = s.backendScope;
    CipherRing? ring;
    if (s.encryptionEnabled) {
      // An empty ring is legal right after joining: the passphrase arrives
      // sealed in our device row and the engine holds pushes until then.
      ring = await CipherRing.fromPassphrases(
        await repo.loadKeyring(),
        keyScope: s.cipherKeyScope,
      );
    }
    var keysEncoded = await repo.loadDeviceKeys();
    if (keysEncoded == null) {
      final fresh = await DeviceKeys.generate();
      keysEncoded = await fresh.encode();
      await repo.saveDeviceKeys(keysEncoded);
    }
    _identity = await DeviceKeys.decode(keysEncoded);
    final adminEncoded = s.syncsRemotely
        ? await repo.loadAdminKey(scope)
        : null;
    _adminKey = adminEncoded == null
        ? null
        : await AdminKey.decode(adminEncoded);
    _trustedAdminPub = s.syncsRemotely ? repo.loadTrustedAdminPub(scope) : null;

    final backend = registry.create(s.backendId);
    try {
      await backend.connect(s.backendConfig);
    } on BackendException catch (e) {
      state = SyncStatus(
        phase: SyncPhase.error,
        lastError: e.message,
        authFailed: e.isAuth,
      );
      await backend.dispose();
      return;
    }
    _backend = backend;

    final engine = SyncEngine(
      backend: backend,
      store: store,
      device: Device(
        id: s.deviceId,
        name: s.deviceName,
        platform: PlatformInfo.name,
        lastSeen: DateTime.now().toUtc(),
        appVersion: BuildInfo.version,
      ),
      identity: _identity,
      adminKey: _adminKey,
      trustedAdminPub: _trustedAdminPub,
      cipherRing: ring,
      onKeyReceived: (version, passphrase) async {
        final current = await repo.loadKeyring();
        current[version] = passphrase;
        await repo.saveKeyring(current);
        ring?.add(
          version,
          await ClipCipher.fromPassphrase(
            passphrase,
            keyScope: s.cipherKeyScope,
          ),
        );
        log.i('encryption key v$version installed');
      },
      pollInterval: Duration(seconds: s.pollIntervalSeconds.clamp(2, 3600)),
      assumeRegistered: s.syncsRemotely && repo.loadRegisteredScope() == scope,
      seenMembershipVersions: s.syncsRemotely
          ? repo.loadSeenVersions(scope)
          : null,
      logger: log.sync,
    );
    _engine = engine;
    _trustSub = engine.trustRequests.listen(
      (t) => ref.read(pendingTrustProvider.notifier).request = t,
    );
    _statusSub = engine.statusStream.listen((st) {
      state = st;
      if (st.phase == SyncPhase.revoked) {
        unawaited(
          _onRevoked(st.revokedReason ?? 'removed', descriptor.displayName),
        );
      }
    });
    _devicesSub = engine.devices.listen((list) {
      _devicesOut.add(list);
      if (s.syncsRemotely) {
        if (repo.loadRegisteredScope() != scope) {
          unawaited(repo.saveRegisteredScope(scope));
        }
        unawaited(repo.saveSeenVersions(scope, engine.seenMembershipVersions));
      }
    });
    _incomingSub = engine.incoming.listen((items) async {
      if (!ref.read(settingsProvider).writeIncomingToClipboard) return;
      final newest = items
          .where((i) => !i.isDeleted)
          .fold<ClipItem?>(
            null,
            (a, b) => a == null || b.createdAt.isAfter(a.createdAt) ? b : a,
          );
      if (newest != null) await _clipboard?.write(newest);
    });
    await engine.start();
    _retention = Timer.periodic(
      const Duration(hours: 12),
      (_) => runRetention(),
    );
    unawaited(runRetention());
  }

  /// The group no longer wants this device: forget the credentials and the
  /// passphrase, fall back to local-only, and tell the user once.
  Future<void> _onRevoked(String reason, String backendName) async {
    final s = ref.read(settingsProvider);
    if (!s.syncsRemotely) return;
    log.w('access revoked ($reason) — forgetting $backendName credentials');
    final repo = ref.read(settingsRepositoryProvider);
    await repo.clearBackendValues(s.backendId);
    await repo.savePassphrase(null);
    await repo.saveRegisteredScope(null);
    await repo.clearGroupTrust(s.backendScope);
    if (!ref.mounted) return;
    ref.read(pendingTrustProvider.notifier).request = null;
    await ref.read(localStoreProvider).resetCursor();
    if (!ref.mounted) return;
    if (!_devicesOut.isClosed) _devicesOut.add(const []);
    // Switching the backend restarts the engine in local-only mode.
    await ref
        .read(settingsProvider.notifier)
        .update(
          (x) => x.copyWith(
            backendId: 'memory',
            backendValues: const {},
            encryptionEnabled: false,
          ),
        );
    if (!ref.mounted) return;
    ref.read(revocationProvider.notifier).notice = RevocationNotice(
      reason: reason,
      backendName: backendName,
    );
  }

  Future<void> _stopEngine() async {
    _retention?.cancel();
    await _statusSub?.cancel();
    await _incomingSub?.cancel();
    await _devicesSub?.cancel();
    await _trustSub?.cancel();
    await _engine?.dispose();
    await _backend?.dispose();
    _engine = null;
    _backend = null;
    if (ref.mounted) state = const SyncStatus.stopped();
  }

  Future<void> _teardown() async {
    await _stopEngine();
    await _captureSub?.cancel();
    await _clipboard?.dispose();
    _clipboard = null;
    await _devicesOut.close();
  }
}
