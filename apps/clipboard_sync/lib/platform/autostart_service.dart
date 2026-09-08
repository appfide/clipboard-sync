import 'dart:io';

import 'package:clipboard_sync/core/logging.dart';
import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';

/// Registers the app to start at login on desktop platforms.
///
/// * macOS — `~/Library/LaunchAgents/com.appfide.clipboardSync.plist`
/// * Linux — `~/.config/autostart/clipboard-sync.desktop`
/// * Windows — `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
abstract final class AutostartService {
  static const _label = 'com.appfide.clipboardSync';
  static const _appName = 'ClipboardSync';

  /// Enables or disables autostart. Errors are logged, never thrown.
  static Future<void> setEnabled({
    required bool enabled,
    required bool hidden,
  }) async {
    try {
      final exe = Platform.resolvedExecutable;
      if (Platform.isMacOS) {
        await _macos(enabled: enabled, hidden: hidden, exe: exe);
      } else if (Platform.isLinux) {
        await _linux(enabled: enabled, hidden: hidden, exe: exe);
      } else if (Platform.isWindows) {
        _windows(enabled: enabled, hidden: hidden, exe: exe);
      }
      log.i('autostart ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      log.w('autostart update failed', error: e);
    }
  }

  static Future<void> _macos({
    required bool enabled,
    required bool hidden,
    required String exe,
  }) async {
    // Resolve the .app bundle so macOS launches it properly.
    final appPath = RegExp(r'^(.*\.app)/').firstMatch(exe)?.group(1) ?? exe;
    final home = Platform.environment['HOME'] ?? '';
    final file = File(p.join(home, 'Library', 'LaunchAgents', '$_label.plist'));
    if (!enabled) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$appPath</string>
    <string>--args</string>
    ${hidden ? '<string>--hidden</string>' : ''}
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
''');
  }

  static Future<void> _linux({
    required bool enabled,
    required bool hidden,
    required String exe,
  }) async {
    final home = Platform.environment['HOME'] ?? '';
    final dir = Directory(
      p.join(
        Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config'),
        'autostart',
      ),
    );
    final file = File(p.join(dir.path, 'clipboard-sync.desktop'));
    if (!enabled) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    dir.createSync(recursive: true);
    file.writeAsStringSync('''
[Desktop Entry]
Type=Application
Name=Clipboard Sync
Exec="$exe"${hidden ? ' --hidden' : ''}
Terminal=false
X-GNOME-Autostart-enabled=true
''');
  }

  static void _windows({
    required bool enabled,
    required bool hidden,
    required String exe,
  }) {
    final hkcu = RegistryKey.openCurrentUser(RegistryAccess.readWrite);
    try {
      final run = hkcu.create(r'Software\Microsoft\Windows\CurrentVersion\Run');
      try {
        if (enabled) {
          run.setValue(
            _appName,
            RegistryValue.string('"$exe"${hidden ? ' --hidden' : ''}'),
          );
        } else if (run.getString(_appName) != null) {
          run.removeValue(_appName);
        }
      } finally {
        run.close();
      }
    } finally {
      hkcu.close();
    }
  }
}
