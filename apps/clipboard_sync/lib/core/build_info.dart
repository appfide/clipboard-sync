/// Build-time constants injected by CI via `--dart-define`.
///
/// `flutter build … --dart-define=APP_VERSION=1.2.3 --dart-define=GIT_SHA=abc`
abstract final class BuildInfo {
  /// Semantic version of this build, `dev` for local runs.
  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  /// Short git SHA of this build.
  static const String gitSha = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'local',
  );

  /// Public repository.
  static const String repoUrl = 'https://github.com/appfide/clipboard-sync';
}
