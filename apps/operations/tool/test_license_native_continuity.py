#!/usr/bin/env python3
"""macOS only: exact native helper, isolated random vault account, separate processes.
No POS startup, restaurant database, enrollment or network. Always deletes fixture.
"""
import hashlib
from pathlib import Path
import subprocess
import tempfile
import uuid

root = Path(__file__).resolve().parents[1]
source = (root / 'macos/Runner/MainFlutterWindow.swift').read_text()
helper = 'enum LicenseNative {' + source.split('enum LicenseNative {', 1)[1]
main = r'''
let account = CommandLine.arguments[1]
let action = CommandLine.arguments[2]
let sample = try LicenseNative.continuity()
if action == "write" {
  let missing = try LicenseNative.read(account: account)
  precondition(missing == nil)
  let record = try JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys])
  try LicenseNative.write(account: account, value: String(data: record, encoding: .utf8)!)
  print("NATIVE_FIXTURE_WRITE_OK")
} else if action == "read" {
  let raw = try LicenseNative.read(account: account)!
  let record = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
  precondition(record["bootId"] as! String == sample["bootId"] as! String)
  precondition((sample["elapsedMs"] as! Int64) >= (record["elapsedMs"] as! NSNumber).int64Value)
  print("NATIVE_FIXTURE_SEPARATE_PROCESS_SAME_BOOT_OK")
  do {
    try LicenseNative.write(account: account, value: String(repeating: "x", count: 2561))
    fatalError("Oversized record was accepted")
  } catch LicenseNative.Failure.invalid { print("NATIVE_FIXTURE_SIZE_BOUND_OK") }
  try LicenseNative.write(account: account, value: "REVOKED")
} else if action == "denied" {
  let value = try LicenseNative.read(account: account)
  precondition(value == "REVOKED")
  print("NATIVE_FIXTURE_SEPARATE_PROCESS_DENIAL_OK")
} else if action == "delete" {
  let status = SecItemDelete(LicenseNative.query(account: account) as CFDictionary)
  precondition(status == errSecSuccess || status == errSecItemNotFound)
  let missing = try LicenseNative.read(account: account)
  precondition(missing == nil)
  print("NATIVE_FIXTURE_DELETED")
}
'''
account = hashlib.sha256(('vynic-license-fixture-' + str(uuid.uuid4())).encode()).hexdigest()
with tempfile.TemporaryDirectory(prefix='vynic-license-native-') as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / 'fixture'
    swift.write_text('import Foundation\nimport Darwin\nimport Security\nimport LocalAuthentication\n' + helper + main)
    subprocess.run(['xcrun', 'swiftc', str(swift), '-o', str(binary)], check=True)
    try:
        for action in ['write', 'read', 'denied']:
            subprocess.run([str(binary), account, action], check=True, timeout=30)
    finally:
        subprocess.run([str(binary), account, 'delete'], check=True, timeout=30)
