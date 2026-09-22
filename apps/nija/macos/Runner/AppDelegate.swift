import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Nija lives in the menu bar: closing the window hides it, it does
  /// not end the session. Returning true here terminated the process the moment
  /// the window went away, tray icon and all, which is not what a close button
  /// means for this app. Quit is the tray's Quit item (or Cmd-Q).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the Dock icon with no visible window brings the window back,
  /// which is the other half of hide-on-close.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if !flag {
      for window in sender.windows where !window.isVisible {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
