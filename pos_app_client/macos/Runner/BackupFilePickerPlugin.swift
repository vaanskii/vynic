import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

public class BackupFilePickerPlugin: NSObject, FlutterPlugin {
  private static var isRegistered = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    guard !isRegistered else { return }
    isRegistered = true

    let channel = FlutterMethodChannel(
      name: "vynic/backup_file_picker",
      binaryMessenger: registrar.messenger
    )
    let instance = BackupFilePickerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    NSLog("[BackupFilePicker] Plugin registered on channel vynic/backup_file_picker")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first else {
      result(
        FlutterError(
          code: "no_window",
          message: "No application window available for file picker",
          details: nil
        )
      )
      return
    }

    switch call.method {
    case "pickRestoreFile":
      BackupFilePickerBridge.pickRestoreFile(window: window, result: result)
    case "pickSaveFile":
      let args = call.arguments as? [String: Any]
      let suggestedName = args?["suggestedName"] as? String
      BackupFilePickerBridge.pickSaveFile(
        window: window,
        suggestedName: suggestedName,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

enum BackupFilePickerBridge {
  static func pickRestoreFile(window: NSWindow, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)

      let panel = NSOpenPanel()
      panel.title = "Select VPOS backup JSON file"
      panel.prompt = "Select backup"
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.allowsMultipleSelection = false
      panel.canCreateDirectories = false
      panel.message = "Choose a VPOS backup (.json) file to restore."
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [UTType.json]
      } else {
        panel.allowedFileTypes = ["json"]
      }

      NSLog("[BackupFilePicker] Showing NSOpenPanel (runModal)")
      let response = panel.runModal()
      NSLog("[BackupFilePicker] NSOpenPanel response: %d", response.rawValue)
      if response == .OK, let url = panel.url {
        result(url.path)
      } else {
        result(nil)
      }
    }
  }

  static func pickSaveFile(
    window: NSWindow,
    suggestedName: String?,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)

      let panel = NSSavePanel()
      panel.title = "Save Backup File"
      panel.prompt = "Save backup"
      panel.canCreateDirectories = true
      panel.nameFieldStringValue = suggestedName ?? "pos_backup.json"
      panel.message = "Choose where to save the VPOS backup (.json) file."
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [UTType.json]
      } else {
        panel.allowedFileTypes = ["json"]
      }

      NSLog("[BackupFilePicker] Showing NSSavePanel (runModal)")
      let response = panel.runModal()
      NSLog("[BackupFilePicker] NSSavePanel response: %d", response.rawValue)
      if response == .OK, let url = panel.url {
        var path = url.path
        if !path.lowercased().hasSuffix(".json") {
          path += ".json"
        }
        result(path)
      } else {
        result(nil)
      }
    }
  }
}
