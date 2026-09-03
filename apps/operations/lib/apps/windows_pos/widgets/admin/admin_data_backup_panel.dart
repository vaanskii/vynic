import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_form_controls.dart';

typedef AsyncVoidCallback = Future<void> Function();

/// Local database backup, and — for the developer only — restore.
///
/// Settings renders this with [allowRestore] false. Taking a copy is the
/// venue's own business and they should do it often; putting one back is not,
/// because restore clears every box first, so a manager reaching for last
/// week's file to "check something" destroys everything entered since. That
/// button lives in the developer section behind a signed token.
class AdminDataBackupPanel extends StatelessWidget {
  const AdminDataBackupPanel({
    super.key,
    required this.lastBackupPath,
    required this.lastRestorePath,
    required this.isCreatingBackup,
    required this.isRestoringBackup,
    required this.onCreateBackupFile,
    required this.onRestoreBackupFromFile,
    this.allowRestore = true,
  });

  final String? lastBackupPath;
  final String? lastRestorePath;
  final bool isCreatingBackup;
  final bool isRestoringBackup;
  final AsyncVoidCallback onCreateBackupFile;
  final AsyncVoidCallback onRestoreBackupFromFile;

  /// Whether the restore button is drawn at all.
  final bool allowRestore;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.save_alt,
                color: AdminDesign.accentDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                allowRestore ? 'სარეზერვო ასლი და აღდგენა' : 'სარეზერვო ასლი',
                style: TextStyle(
                  color: AdminDesign.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'მოიცავს მომხმარებლებს, მენიუს, მაგიდებს, გაყიდვებს, პაკეტებს, ჯავშნებსა და პარამეტრებს.',
            style: TextStyle(color: AdminDesign.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (lastBackupPath != null)
            SelectableText(
              'ბოლო ასლი: $lastBackupPath',
              style: const TextStyle(
                color: AdminDesign.accentDark,
                fontSize: 12,
              ),
            ),
          if (allowRestore && lastRestorePath != null)
            SelectableText(
              'ბოლო აღდგენა: $lastRestorePath',
              style: const TextStyle(
                color: AdminTones.successText,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 12),
          AdminActionRow(
            children: [
              SizedBox(
                width: 330,
                child: ElevatedButton.icon(
                  onPressed: isCreatingBackup
                      ? null
                      : () async {
                          debugPrint('[BackupUI] Save backup button clicked');
                          try {
                            await onCreateBackupFile();
                            debugPrint(
                              '[BackupUI] Save backup callback finished',
                            );
                          } catch (e, st) {
                            debugPrint(
                              '[BackupUI] Save backup callback error: $e',
                            );
                            debugPrint('$st');
                          }
                        },
                  style: AdminFormButtons.primary(),
                  icon: const Icon(Icons.cloud_download, size: 20),
                  label: Text(
                    isCreatingBackup ? 'შექმნა...' : 'სარეზერვო ფაილის შექმნა',
                  ),
                ),
              ),
              if (allowRestore)
                SizedBox(
                  width: 330,
                  child: OutlinedButton.icon(
                    onPressed: isRestoringBackup
                        ? null
                        : () async {
                            debugPrint(
                              '[BackupUI] Restore backup button clicked',
                            );
                            try {
                              await onRestoreBackupFromFile();
                              debugPrint(
                                '[BackupUI] Restore backup callback finished',
                              );
                            } catch (e, st) {
                              debugPrint(
                                '[BackupUI] Restore backup callback error: $e',
                              );
                              debugPrint('$st');
                            }
                          },
                    style: AdminFormButtons.outline(),
                    icon: const Icon(Icons.restore, size: 20),
                    label: Text(
                      isRestoringBackup
                          ? 'აღდგენა...'
                          : 'სარეზერვო ასლიდან აღდგენა',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
