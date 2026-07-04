import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-platform backup file dialogs.
/// macOS uses a native NSOpenPanel/NSSavePanel (sandbox-safe with entitlements).
class BackupFilePicker {
  BackupFilePicker._();

  static const MethodChannel _macChannel = MethodChannel(
    'vynic/backup_file_picker',
  );

  static String _defaultBackupName() {
    return 'pos_backup_${DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-')}.json';
  }

  static Future<String?> pickRestoreFile() async {
    if (Platform.isMacOS) {
      try {
        debugPrint('[BackupFilePicker] macOS native pickRestoreFile');
        final path = await _macChannel.invokeMethod<String>('pickRestoreFile');
        debugPrint('[BackupFilePicker] macOS native path: $path');
        return path;
      } catch (e, st) {
        debugPrint('[BackupFilePicker] macOS native pick failed: $e\n$st');
      }
    }

    return _pickRestoreWithPlugins();
  }

  static Future<String?> pickSaveFile() async {
    if (Platform.isMacOS) {
      try {
        debugPrint('[BackupFilePicker] macOS native pickSaveFile');
        final path = await _macChannel.invokeMethod<String>(
          'pickSaveFile',
          {'suggestedName': _defaultBackupName()},
        );
        debugPrint('[BackupFilePicker] macOS native save path: $path');
        return path;
      } catch (e, st) {
        debugPrint('[BackupFilePicker] macOS native save failed: $e\n$st');
      }
    }

    return _pickSaveWithPlugins();
  }

  static Future<String?> _pickRestoreWithPlugins() async {
    const jsonGroup = fs.XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      mimeTypes: ['application/json', 'text/json'],
      uniformTypeIdentifiers: ['public.json'],
    );

    if (!Platform.isWindows) {
      try {
        debugPrint('[BackupFilePicker] file_selector.openFile');
        final selected = await fs
            .openFile(
              acceptedTypeGroups: const [jsonGroup],
              confirmButtonText: 'Select backup',
            )
            .timeout(const Duration(seconds: 15));
        final path = selected?.path;
        if (path != null && path.isNotEmpty) return path;
      } catch (e) {
        debugPrint('[BackupFilePicker] file_selector open failed: $e');
      }
    }

    try {
      debugPrint('[BackupFilePicker] FilePicker.pickFiles');
      final pickerResult = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select VPOS backup JSON file',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: false,
      );
      if (pickerResult == null || pickerResult.files.isEmpty) return null;
      return pickerResult.files.single.path;
    } catch (e) {
      debugPrint('[BackupFilePicker] FilePicker open failed: $e');
      return null;
    }
  }

  static Future<String?> _pickSaveWithPlugins() async {
    const jsonGroup = fs.XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      mimeTypes: ['application/json', 'text/json'],
      uniformTypeIdentifiers: ['public.json'],
    );
    final suggestedName = _defaultBackupName();

    if (!Platform.isWindows) {
      try {
        debugPrint('[BackupFilePicker] file_selector.getSaveLocation');
        final location = await fs
            .getSaveLocation(
              acceptedTypeGroups: const [jsonGroup],
              suggestedName: suggestedName,
              confirmButtonText: 'Save backup',
            )
            .timeout(const Duration(seconds: 15));
        final path = location?.path;
        if (path != null && path.isNotEmpty) return path;
      } catch (e) {
        debugPrint('[BackupFilePicker] file_selector save failed: $e');
      }
    }

    try {
      debugPrint('[BackupFilePicker] FilePicker.saveFile');
      return FilePicker.platform.saveFile(
        dialogTitle: 'Save Backup File',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
    } catch (e) {
      debugPrint('[BackupFilePicker] FilePicker save failed: $e');
      return null;
    }
  }
}
