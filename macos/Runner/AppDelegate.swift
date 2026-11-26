import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Held for the life of the process so App Nap does not throttle the timers
  /// that watch the pointer and the clipboard while no window is on screen.
  private var backgroundActivity: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    backgroundActivity = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep,
      reason: "Watching the clipboard and the top screen edge"
    )
    super.applicationDidFinishLaunching(notification)
  }

  // The app keeps running from the menu bar when its panel is hidden.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
