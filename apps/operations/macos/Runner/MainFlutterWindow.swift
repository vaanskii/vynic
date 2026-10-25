import Cocoa
import Security
import LocalAuthentication
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let licenseChannel = FlutterMethodChannel(name: "ge.vynic/license", binaryMessenger: flutterViewController.engine.binaryMessenger)
    licenseChannel.setMethodCallHandler { call, result in
      if call.method == "elapsed" || call.method == "continuity" {
        do {
          let sample = try LicenseNative.continuity()
          result(call.method == "elapsed" ? sample["elapsedMs"] : sample)
        } catch { result(FlutterError(code: "continuity_unavailable", message: "Trusted clock unavailable", details: nil)) }
      } else if call.method == "readAnchor" || call.method == "writeAnchor" {
        guard let arguments = call.arguments as? [String: Any],
              let account = arguments["account"] as? String,
              account.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
          result(FlutterError(code: "invalid_anchor", message: "Invalid vault account", details: nil)); return
        }
        do {
          if call.method == "readAnchor" { result(try LicenseNative.read(account: account)) }
          else {
            guard let value = arguments["value"] as? String else { throw LicenseNative.Failure.invalid }
            try LicenseNative.write(account: account, value: value)
            result(nil)
          }
        } catch { result(FlutterError(code: "vault_unavailable", message: "License vault unavailable", details: nil)) }
      } else if call.method == "purchase" {
        if NSWorkspace.shared.open(URL(string: "https://vynic.ge/pricing")!) { result(nil) }
        else { result(FlutterError(code: "open_failed", message: "Could not open website", details: nil)) }
      } else { result(FlutterMethodNotImplemented) }
    }
    RegisterGeneratedPlugins(registry: flutterViewController)
    BackupFilePickerPlugin.register(
      with: flutterViewController.registrar(forPlugin: "BackupFilePickerPlugin")
    )

    super.awakeFromNib()
  }
}

// Kept free of Flutter types so the exact implementation can be tested by a
// separate native fixture process without opening or installing the POS.
enum LicenseNative {
  enum Failure: Error { case invalid, unavailable }
  static let service = "ge.vynic.subscription-license"
  static func continuity() throws -> [String: Any] {
    var size = 0
    guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0,
          size > 1, size < 128 else { throw Failure.unavailable }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { throw Failure.unavailable }
    let boot = String(cString: bytes)
    guard UUID(uuidString: boot) != nil else { throw Failure.unavailable }
    var info = mach_timebase_info_data_t()
    guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom > 0 else { throw Failure.unavailable }
    let ms = Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000
    return ["elapsedMs": Int64(ms), "bootId": boot]
  }
  static func query(account: String) -> [String: Any] {
    let context = LAContext()
    context.interactionNotAllowed = true
    return [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: account,
     kSecAttrSynchronizable as String: false,
     kSecUseAuthenticationContext as String: context]
  }
  static func read(account: String) throws -> String? {
    var q = query(account: account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
          let value = String(data: data, encoding: .utf8) else { throw Failure.unavailable }
    return value
  }
  static func write(account: String, value: String) throws {
    let data = Data(value.utf8)
    // Match Credential Manager's bound; never silently truncate an anchor.
    guard data.count <= 2560 else { throw Failure.invalid }
    let q = query(account: account)
    let values = [kSecValueData as String: data]
    var status = SecItemUpdate(q as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var insert = q
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(insert as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw Failure.unavailable }
  }
}
