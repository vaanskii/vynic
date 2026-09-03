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
        final path = await _macChannel.invokeMethod<String>('pickSaveFile', {
          'suggestedName': _defaultBackupName(),
        });
        debugPrint('[BackupFilePicker] macOS native save path: $path');
        return path;
      } catch (e, st) {
        debugPrint('[BackupFilePicker] macOS native save failed: $e\n$st');
      }
    }

    return _pickSaveWithPlugins();
  }

  /// Picks an image file — the venue's receipt logo.
  ///
  /// Deliberately not routed through the macOS native channel: that one is a
  /// backup-specific panel filtered to JSON. This uses the cross-platform
  /// pickers, which is enough for a file the operator chooses once.
  static Future<String?> pickImageFile() async {
    const imageGroup = fs.XTypeGroup(
      label: 'Image',
      extensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
      mimeTypes: ['image/png', 'image/jpeg', 'image/bmp', 'image/webp'],
      uniformTypeIdentifiers: ['public.image'],
    );

    if (!Platform.isWindows) {
      try {
        final selected = await fs
            .openFile(
              acceptedTypeGroups: const [imageGroup],
              confirmButtonText: 'Select logo',
            )
            .timeout(const Duration(seconds: 30));
        final path = selected?.path;
        if (path != null && path.isNotEmpty) return path;
      } catch (e) {
        debugPrint('[BackupFilePicker] file_selector image open failed: $e');
      }
    }

    try {
      final pickerResult = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select receipt logo',
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
        withData: false,
      );
      if (pickerResult == null || pickerResult.files.isEmpty) return null;
      return pickerResult.files.single.path;
    } catch (e) {
      debugPrint('[BackupFilePicker] FilePicker image open failed: $e');
      return null;
    }
  }

  /// Where to write the venue's logo out to.
  ///
  /// A logo lives in the database and nowhere else once the source file is
  /// gone, so exporting it is the difference between „reinstall the POS" and
  /// „find the designer's original".
  static Future<String?> pickSaveImageFile({
    String suggestedName = 'logo.png',
  }) async {
    const pngGroup = fs.XTypeGroup(
      label: 'PNG',
      extensions: ['png'],
      mimeTypes: ['image/png'],
      uniformTypeIdentifiers: ['public.png'],
    );

    try {
      final location = await fs.getSaveLocation(
        acceptedTypeGroups: const [pngGroup],
        suggestedName: suggestedName,
      );
      final path = location?.path;
      if (path != null && path.isNotEmpty) return path;
    } catch (e) {
      debugPrint('[BackupFilePicker] file_selector save image failed: $e');
    }

    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: 'Export receipt logo',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
    } catch (e) {
      debugPrint('[BackupFilePicker] FilePicker save image failed: $e');
      return null;
    }
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
