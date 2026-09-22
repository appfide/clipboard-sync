/// Model for the newest GitHub release and the installers it ships.
///
/// Pure Dart on purpose: the mapping from asset file names to platforms is the
/// part worth testing, and it must not need a widget test to exercise.
library;

/// A platform Clipboard Sync ships installers for.
enum DownloadPlatform {
  /// macOS desktop.
  macos('macOS'),

  /// Windows desktop.
  windows('Windows'),

  /// Linux desktop.
  linux('Linux'),

  /// Android phones and tablets.
  android('Android'),

  /// iPhone and iPad.
  ios('iOS');

  const DownloadPlatform(this.label);

  /// Human name for the section header.
  final String label;

  /// The platform matching `Platform.operatingSystem`, or null when the host
  /// is something the release does not cover.
  static DownloadPlatform? fromOperatingSystem(String os) => switch (os) {
    'macos' => DownloadPlatform.macos,
    'windows' => DownloadPlatform.windows,
    'linux' => DownloadPlatform.linux,
    'android' => DownloadPlatform.android,
    'ios' => DownloadPlatform.ios,
    _ => null,
  };
}

/// One downloadable file from a release.
class DownloadAsset {
  /// Creates an asset.
  const DownloadAsset({
    required this.name,
    required this.url,
    required this.sizeBytes,
    required this.platform,
    required this.label,
    this.note,
  });

  /// File name, e.g. `ClipboardSync-0.2.1-macos.dmg`.
  final String name;

  /// Direct download URL.
  final String url;

  /// Size on disk; 0 when the API did not report one.
  final int sizeBytes;

  /// Platform this file installs on.
  final DownloadPlatform platform;

  /// What the file is, e.g. `Disk image (.dmg)`.
  final String label;

  /// Caveat worth showing under the row.
  final String? note;

  /// `12.4 MB`, or an empty string when the size is unknown.
  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    const mb = 1024 * 1024;
    if (sizeBytes >= mb) return '${(sizeBytes / mb).toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).round()} KB';
  }
}

/// What a release asset's file name says about it. Returns null for files that
/// are not installers — `.aab` (a Play Store upload, not installable) and the
/// checksum list, which the page links separately.
({DownloadPlatform platform, String label, String? note})? _classify(
  String name,
) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.dmg')) {
    return (
      platform: DownloadPlatform.macos,
      label: 'Disk image (.dmg)',
      note: 'Apple silicon — Intel Macs run it under Rosetta.',
    );
  }
  if (lower.endsWith('.exe')) {
    return (
      platform: DownloadPlatform.windows,
      label: 'Installer (.exe)',
      note: null,
    );
  }
  if (lower.endsWith('.zip')) {
    return (
      platform: DownloadPlatform.windows,
      label: 'Portable (.zip)',
      note: 'Unpack and run — no installer, no admin rights.',
    );
  }
  if (lower.endsWith('.deb')) {
    return (
      platform: DownloadPlatform.linux,
      label: 'Debian package (.deb)',
      note: 'Debian, Ubuntu and derivatives.',
    );
  }
  if (lower.endsWith('.appimage')) {
    return (
      platform: DownloadPlatform.linux,
      label: 'AppImage',
      note: 'Any distribution — mark it executable and run it.',
    );
  }
  if (lower.endsWith('.apk')) {
    return (
      platform: DownloadPlatform.android,
      label: 'APK',
      note: 'Android asks you to allow installs from this source once.',
    );
  }
  if (lower.endsWith('.ipa')) {
    return (
      platform: DownloadPlatform.ios,
      label: 'Unsigned IPA',
      note: 'Needs AltStore or Sideloadly and your own Apple ID.',
    );
  }
  return null;
}

/// The newest release, as the download page needs it.
class ReleaseInfo {
  /// Creates a release.
  const ReleaseInfo({
    required this.version,
    required this.htmlUrl,
    required this.assets,
    this.publishedAt,
    this.checksumsUrl,
  });

  /// Reads the payload of `GET /repos/{owner}/{repo}/releases/latest`.
  factory ReleaseInfo.fromJson(Map<String, Object?> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final assets = <DownloadAsset>[];
    String? checksums;

    for (final entry in (json['assets'] as List<Object?>? ?? const [])) {
      if (entry is! Map<String, Object?>) continue;
      final name = entry['name'] as String? ?? '';
      final url = entry['browser_download_url'] as String? ?? '';
      if (name.isEmpty || url.isEmpty) continue;
      if (name.toLowerCase().startsWith('sha256sums')) {
        checksums = url;
        continue;
      }
      final kind = _classify(name);
      if (kind == null) continue;
      assets.add(
        DownloadAsset(
          name: name,
          url: url,
          sizeBytes: (entry['size'] as num?)?.toInt() ?? 0,
          platform: kind.platform,
          label: kind.label,
          note: kind.note,
        ),
      );
    }

    final published = json['published_at'] as String?;
    return ReleaseInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      htmlUrl: json['html_url'] as String? ?? '',
      assets: assets,
      publishedAt: published == null ? null : DateTime.tryParse(published),
      checksumsUrl: checksums,
    );
  }

  /// Version without the leading `v`, e.g. `0.2.1`.
  final String version;

  /// Release page on GitHub.
  final String htmlUrl;

  /// When the release was published.
  final DateTime? publishedAt;

  /// Installers, in the order GitHub listed them.
  final List<DownloadAsset> assets;

  /// `SHA256SUMS.txt`, when the release carries one.
  final String? checksumsUrl;

  /// Installers for [platform].
  List<DownloadAsset> forPlatform(DownloadPlatform platform) =>
      assets.where((a) => a.platform == platform).toList();

  /// Platforms with at least one installer, in enum order.
  List<DownloadPlatform> get platforms => DownloadPlatform.values
      .where((p) => assets.any((a) => a.platform == p))
      .toList();

  /// Whether this release is newer than [current].
  ///
  /// False whenever either side is not a plain `x.y.z`, which covers local
  /// builds where `BuildInfo.version` is `dev`.
  bool isNewerThan(String current) {
    final a = _parseVersion(version);
    final b = _parseVersion(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int>? _parseVersion(String value) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(value.trim());
    if (match == null) return null;
    return [
      for (var g = 1; g <= 3; g++) int.parse(match.group(g)!),
    ];
  }
}
