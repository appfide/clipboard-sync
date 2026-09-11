import 'dart:async';
import 'dart:io';

import 'package:clipboard_sync/core/logging.dart';
import 'package:clipboard_sync/core/platform_info.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Tray icon, hide-to-tray window behaviour and the global hotkey.
///
/// No-op on mobile.
class DesktopShell with TrayListener, WindowListener {
  /// Creates the shell; call [init] after `runApp`.
  DesktopShell({
    required this.onSyncNow,
    required this.onOpenSettings,
    required this.onQuit,
    required this.onTogglePause,
  });

  /// Tray "Sync now".
  final Future<void> Function() onSyncNow;

  /// Tray "Pause capture" / "Resume capture".
  final Future<void> Function() onTogglePause;

  /// Tray "Settings…".
  final void Function() onOpenSettings;

  /// Tray "Quit".
  final Future<void> Function() onQuit;

  static const _menuShow = 'show';
  static const _menuSync = 'sync';
  static const _menuPause = 'pause';
  static const _menuSettings = 'settings';
  static const _menuQuit = 'quit';

  bool _initialised = false;
  bool _paused = false;
  bool _trayReady = false;
  HotKey? _hotKey;

  /// Prepares the window before the first frame. Call in `main()` before
  /// `runApp` on desktop.
  static Future<void> prepareWindow({required bool startHidden}) async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1040, 720),
      minimumSize: Size(400, 520),
      center: true,
      title: 'Clipboard Sync',
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (!startHidden) {
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  /// Sets up tray, close-to-tray and hotkey.
  Future<void> init({required bool hotkeyEnabled, bool paused = false}) async {
    if (!PlatformInfo.isDesktop || _initialised) return;
    _initialised = true;
    _paused = paused;
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/icons/tray.ico' : 'assets/icons/tray.png',
        isTemplate: Platform.isMacOS,
      );
      await trayManager.setToolTip('Clipboard Sync');
      await trayManager.setContextMenu(_menu());
      trayManager.addListener(this);
      _trayReady = true;
    } catch (e) {
      log.w('tray unavailable', error: e);
    }

    await setHotkeyEnabled(enabled: hotkeyEnabled);
  }

  Menu _menu() => Menu(
    items: [
      MenuItem(key: _menuShow, label: 'Open Clipboard Sync'),
      MenuItem(key: _menuSync, label: 'Sync now'),
      MenuItem(
        key: _menuPause,
        label: _paused ? 'Resume capture' : 'Pause capture',
      ),
      MenuItem(key: _menuSettings, label: 'Settings…'),
      MenuItem.separator(),
      MenuItem(key: _menuQuit, label: 'Quit'),
    ],
  );

  /// Reflects the pause state in the tray menu and tooltip.
  Future<void> setPaused({required bool paused}) async {
    if (!PlatformInfo.isDesktop || _paused == paused) return;
    _paused = paused;
    if (!_trayReady) return;
    try {
      await trayManager.setContextMenu(_menu());
      await trayManager.setToolTip(
        paused ? 'Clipboard Sync — capture paused' : 'Clipboard Sync',
      );
    } catch (e) {
      log.w('tray update failed', error: e);
    }
  }

  /// Registers or unregisters the global hotkey (Ctrl/Cmd+Shift+V).
  Future<void> setHotkeyEnabled({required bool enabled}) async {
    if (!PlatformInfo.isDesktop) return;
    try {
      await hotKeyManager.unregisterAll();
      _hotKey = null;
      if (!enabled) return;
      final hk = HotKey(
        key: PhysicalKeyboardKey.keyV,
        modifiers: [
          if (Platform.isMacOS) HotKeyModifier.meta else HotKeyModifier.control,
          HotKeyModifier.shift,
        ],
      );
      await hotKeyManager.register(hk, keyDownHandler: (_) => showWindow());
      _hotKey = hk;
    } catch (e) {
      log.w('hotkey registration failed', error: e);
    }
  }

  /// Human-readable hotkey label.
  String get hotkeyLabel => Platform.isMacOS ? '⌘⇧V' : 'Ctrl+Shift+V';

  /// Brings the window to front.
  Future<void> showWindow() async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.show();
    await windowManager.focus();
  }

  /// Hides the window to the tray.
  Future<void> hideWindow() async {
    if (!PlatformInfo.isDesktop) return;
    await windowManager.hide();
  }

  /// Tears down tray/hotkey (before quitting).
  Future<void> dispose() async {
    if (!_initialised) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await hotKeyManager.unregisterAll();
    await trayManager.destroy();
    _initialised = false;
  }

  @override
  void onWindowClose() => unawaited(hideWindow());

  @override
  void onTrayIconMouseDown() {
    if (Platform.isLinux) {
      unawaited(trayManager.popUpContextMenu());
    } else {
      unawaited(showWindow());
    }
  }

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _menuShow:
        unawaited(showWindow());
      case _menuSync:
        unawaited(onSyncNow());
      case _menuPause:
        unawaited(onTogglePause());
      case _menuSettings:
        unawaited(showWindow());
        onOpenSettings();
      case _menuQuit:
        unawaited(onQuit());
    }
  }

  /// Whether a hotkey is registered.
  bool get hotkeyActive => _hotKey != null;
}
