import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_form_controls.dart';

typedef AsyncVoidCallback = Future<void> Function();

/// Local database backup and restore.
///
/// This lived at the bottom of the Settings tab, where it sat next to service
/// fee and language options that have nothing to do with it. It now renders in
/// the connection section alongside the other terminal-level plumbing (backend
/// URL, sync status, print host). Same two callbacks, same busy flags — only
/// the parent and the surrounding chrome changed.
class AdminDataBackupPanel extends StatelessWidget {
  const AdminDataBackupPanel({
    super.key,
    required this.lastBackupPath,
    required this.lastRestorePath,
    required this.isCreatingBackup,
    required this.isRestoringBackup,
    required this.onCreateBackupFile,
    required this.onRestoreBackupFromFile,
  });

  final String? lastBackupPath;
  final String? lastRestorePath;
  final bool isCreatingBackup;
  final bool isRestoringBackup;
  final AsyncVoidCallback onCreateBackupFile;
  final AsyncVoidCallback onRestoreBackupFromFile;

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
              const Text(
                'სარეზერვო ასლი და აღდგენა',
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
          if (lastRestorePath != null)
            SelectableText(
              'ბოლო აღდგენა: $lastRestorePath',
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
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
