import 'package:meta/meta.dart';

/// Engine state.
enum SyncPhase {
  /// Not started or stopped.
  stopped,

  /// Connected, nothing in flight.
  idle,

  /// Push or pull in progress.
  syncing,

  /// Last operation failed; will retry unless [SyncStatus.authFailed].
  error,
}

/// Snapshot of engine state for the UI.
@immutable
class SyncStatus {
  /// Creates a status.
  const SyncStatus({
    required this.phase,
    this.lastSyncAt,
    this.lastError,
    this.pendingCount = 0,
    this.authFailed = false,
    this.realtime = false,
  });

  /// Initial status.
  const SyncStatus.stopped() : this(phase: SyncPhase.stopped);

  /// Current phase.
  final SyncPhase phase;

  /// Last successful push or pull (UTC).
  final DateTime? lastSyncAt;

  /// Redacted last error message.
  final String? lastError;

  /// Items waiting in the outbox.
  final int pendingCount;

  /// Credentials rejected — retries paused until settings change.
  final bool authFailed;

  /// Whether a realtime subscription is active.
  final bool realtime;

  /// Copy with fields replaced.
  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    String? lastError,
    int? pendingCount,
    bool? authFailed,
    bool? realtime,
    bool clearError = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
    pendingCount: pendingCount ?? this.pendingCount,
    authFailed: authFailed ?? this.authFailed,
    realtime: realtime ?? this.realtime,
  );

  @override
  String toString() =>
      'SyncStatus($phase, pending=$pendingCount'
      '${lastError != null ? ', error=$lastError' : ''})';
}
