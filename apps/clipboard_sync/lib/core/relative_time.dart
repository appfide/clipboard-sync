/// Small helpers for "5 min ago" / "in 3 h" labels.
abstract final class RelativeTime {
  /// How long ago [t] was, coarse.
  static String ago(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now().toUtc()).difference(t.toUtc());
    if (d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 30) return '${d.inDays} d ago';
    return '${d.inDays ~/ 30} mo ago';
  }

  /// How far in the future [t] is, coarse.
  static String until(DateTime t, {DateTime? now}) {
    final d = t.toUtc().difference(now ?? DateTime.now().toUtc());
    if (d.isNegative) return 'expired';
    if (d.inMinutes < 1) return 'under a minute';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 48) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  /// `m:ss` countdown.
  static String countdown(Duration d) {
    if (d.isNegative) return '0:00';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
