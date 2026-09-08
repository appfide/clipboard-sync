/// Masks credentials before they reach logs or bug reports.
///
/// Applied to every log line and to the diagnostics export in the app.
String redactSecrets(String input) {
  var out = input;
  for (final re in _patterns) {
    out = out.replaceAllMapped(re, (m) => _mask(m.group(0)!));
  }
  return out;
}

String _mask(String s) {
  if (s.length <= 8) return '***';
  return '${s.substring(0, 4)}…${s.substring(s.length - 2)}';
}

final List<RegExp> _patterns = <RegExp>[
  // JWTs (Supabase legacy keys, Firebase id tokens, PocketBase tokens).
  RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'),
  // Supabase new-style keys.
  RegExp('sb_(publishable|secret)_[A-Za-z0-9_-]{20,}'),
  // Google / Firebase API keys.
  RegExp('AIza[0-9A-Za-z_-]{35}'),
  // Credentials embedded in URLs (mongodb://u:p@, https://u:p@couch).
  RegExp(r'(?<=://)[^\s:/@]+:[^\s@]+(?=@)'),
  // Bearer / Basic auth headers.
  RegExp('(?<=(Bearer|Basic) )[A-Za-z0-9+/=_.-]{8,}'),
  // Generic key=value secrets.
  RegExp(
    r'(?<=(password|passwd|secret|token|api[_-]?key|anon[_-]?key)["\s]*[:=]["\s]*)[^\s"&,]{4,}',
    caseSensitive: false,
  ),
];
