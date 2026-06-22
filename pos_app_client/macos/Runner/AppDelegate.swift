import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      BackupFilePickerPlugin.register(
        with: controller.registrar(forPlugin: "BackupFilePickerPlugin")
      )
    } else {
      NSLog("[BackupFilePicker] AppDelegate could not register plugin (no FlutterViewController yet)")
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
