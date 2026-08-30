import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_connection_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_developer_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_error_log_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/printers/admin_printers_section.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/developer_unlock_dialog.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/backup_file_picker.dart';
import 'package:vynic/core/services/printing/printer_service.dart';
import 'package:vynic/core/services/security/developer_access.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

/// The developer tools as a screen of their own, reachable from the login
/// screen without signing in.
///
/// This is the route that matters for support. Reaching the tools through the
/// admin panel needs a manager's PIN — which is exactly what the venue does not
/// have on the day they phone up locked out. The token is the authority here,
/// not the login, so nothing is lost by putting the door before it.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  /// Prompts for a token and, if it verifies, opens the tools.
  ///
  /// Returns without pushing anything when the dialog is dismissed, so the
  /// caller can wire this straight to a hidden gesture.
  static Future<void> unlockAndOpen(BuildContext context) async {
    if (!DeveloperAccess.isUnlocked) {
      final unlocked = await DeveloperUnlockDialog.show(context);
      if (!unlocked) return;
    }
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DeveloperScreen()));
  }

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  bool _isCreatingBackup = false;
  bool _isRestoringBackup = false;
  String? _lastBackupPath;
  String? _lastRestorePath;

  String _selectedSection = 'developer';

  final TextEditingController _kitchenPrinterController =
      TextEditingController();
  final TextEditingController _receiptPrinterController =
      TextEditingController();
  final TextEditingController _printerPortController = TextEditingController();
  bool _isSavingPrinterSettings = false;
  bool _isTestingPrinters = false;

  @override
  void initState() {
    super.initState();
    DeveloperAccess.unlocked.addListener(_onAccessChanged);
    _kitchenPrinterController.text = DatabaseService.getKitchenPrinterIp();
    _receiptPrinterController.text = DatabaseService.getReceiptPrinterIp();
    _printerPortController.text = DatabaseService.getPrinterPort().toString();
  }

  @override
  void dispose() {
    DeveloperAccess.unlocked.removeListener(_onAccessChanged);
    _kitchenPrinterController.dispose();
    _receiptPrinterController.dispose();
    _printerPortController.dispose();
    super.dispose();
  }

  Future<void> _savePrinterSettings() async {
    setState(() => _isSavingPrinterSettings = true);
    try {
      await DatabaseService.savePrinterConfiguration(
        kitchenIp: _kitchenPrinterController.text.trim(),
        receiptIp: _receiptPrinterController.text.trim(),
        port: 9100,
      );
      await PrinterService.initialize(forceReconnect: true);
      if (!mounted) return;
      unawaited(showSuccessToast(context, 'Printer settings saved.'));
      await DeveloperAccess.logAction('printers.save');
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Could not save printers: $e'));
    } finally {
      if (mounted) setState(() => _isSavingPrinterSettings = false);
    }
  }

  Future<void> _testPrinterConnections() async {
    setState(() => _isTestingPrinters = true);
    try {
      await PrinterService.initialize(forceReconnect: true);
      if (!mounted) return;
      unawaited(showSuccessToast(context, 'Printer connection test finished.'));
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Printer test failed: $e'));
    } finally {
      if (mounted) setState(() => _isTestingPrinters = false);
    }
  }

  /// Locking — by the button, or by the token running out mid-session — closes
  /// the screen rather than leaving the tools on display behind a dead session.
  void _onAccessChanged() {
    if (!mounted || DeveloperAccess.isUnlocked) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _createBackupFile() async {
    if (kIsWeb || _isCreatingBackup) return;

    final targetPath = await BackupFilePicker.pickSaveFile();
    if (targetPath == null || targetPath.isEmpty) return;

    setState(() => _isCreatingBackup = true);
    try {
      final file = await DatabaseService.createDataBackup(
        targetFilePath: targetPath,
      );
      if (!mounted) return;
      setState(() => _lastBackupPath = file.path);
      unawaited(showSuccessToast(context, 'Backup written to ${file.path}'));
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Backup failed: $e'));
    } finally {
      if (mounted) setState(() => _isCreatingBackup = false);
    }
  }

  Future<void> _restoreBackupFromFile() async {
    if (kIsWeb || _isRestoringBackup) return;

    final resolvedPath = await BackupFilePicker.pickRestoreFile();
    if (resolvedPath == null || resolvedPath.isEmpty) return;

    final backupFile = File(resolvedPath);
    if (!await backupFile.exists()) {
      if (!mounted) return;
      unawaited(
        showErrorToast(context, 'Backup file not found at $resolvedPath'),
      );
      return;
    }

    setState(() => _isRestoringBackup = true);
    try {
      await DatabaseService.restoreDataBackupFromFile(backupFile);
      if (!mounted) return;
      setState(() => _lastRestorePath = resolvedPath);
      unawaited(
        showSuccessToast(
          context,
          'Restored. Restart the terminal so every screen reloads.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      unawaited(showErrorToast(context, 'Restore failed: $e'));
    } finally {
      if (mounted) setState(() => _isRestoringBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AdminTheme.of(context),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AdminDesign.surface,
          appBar: AppBar(
            backgroundColor: AdminDesign.panel,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: AdminDesign.text),
            title: const Text(
              'Vynic — developer',
              style: TextStyle(
                color: AdminDesign.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            shape: const Border(bottom: BorderSide(color: AdminDesign.border)),
          ),
          body: Row(
            children: [
              _buildSidebar(),
              Expanded(child: ClipRect(child: _buildContent())),
            ],
          ),
        ),
      ),
    );
  }

  static const _sections = <String, ({IconData icon, String label})>{
    'developer': (icon: Icons.engineering_outlined, label: 'Tools'),
    'errors': (icon: Icons.bug_report, label: 'შეცდომები'),
    'printers': (icon: Icons.print, label: 'პრინტერები'),
    'connection': (icon: Icons.lan_outlined, label: 'კავშირი'),
  };

  Widget _buildSidebar() {
    return Container(
      width: 190,
      decoration: const BoxDecoration(
        color: AdminDesign.panel,
        border: Border(right: BorderSide(color: AdminDesign.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        children: [
          for (final entry in _sections.entries)
            _buildMenuItem(entry.key, entry.value.icon, entry.value.label),
        ],
      ),
    );
  }

  Widget _buildMenuItem(String section, IconData icon, String label) {
    final isSelected = _selectedSection == section;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isSelected ? VynicFloorTokens.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selectedSection = section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? AdminDesign.accentDark
                      : AdminDesign.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? VynicFloorTokens.accentText
                          : AdminDesign.muted,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedSection) {
      case 'errors':
        return const AdminErrorLogSection();
      case 'printers':
        return AdminPrintersSection(
          kitchenPrinterController: _kitchenPrinterController,
          receiptPrinterController: _receiptPrinterController,
          printerPortController: _printerPortController,
          isSavingPrinterSettings: _isSavingPrinterSettings,
          isTestingPrinters: _isTestingPrinters,
          onSavePrinterSettings: _savePrinterSettings,
          onTestPrinterConnections: _testPrinterConnections,
        );
      case 'connection':
        return const AdminConnectionSection();
      case 'developer':
      default:
        return AdminDeveloperSection(
          onCreateBackupFile: _createBackupFile,
          onRestoreBackupFromFile: _restoreBackupFromFile,
          isCreatingBackup: _isCreatingBackup,
          isRestoringBackup: _isRestoringBackup,
          lastBackupPath: _lastBackupPath,
          lastRestorePath: _lastRestorePath,
        );
    }
  }
}
