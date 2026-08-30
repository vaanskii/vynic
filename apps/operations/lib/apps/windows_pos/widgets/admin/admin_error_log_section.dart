import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

class AdminErrorLogSection extends StatefulWidget {
  const AdminErrorLogSection({super.key});

  @override
  State<AdminErrorLogSection> createState() => _AdminErrorLogSectionState();
}

class _AdminErrorLogSectionState extends State<AdminErrorLogSection> {
  static const Color _secondaryColor = AdminDesign.accentDark;
  static const Color _surfaceColor = AdminDesign.panelSoft;
  static const Color _cardColor = AdminDesign.panel;
  static const Color _borderColor = AdminDesign.border;
  static const Color _textPrimary = AdminDesign.text;
  static const Color _textMuted = AdminDesign.muted;

  @override
  Widget build(BuildContext context) {
    final logs = DatabaseService.getErrorLogs();

    return SizedBox.expand(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: adminSectionMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminSectionHeader(
                  icon: Icons.bug_report_outlined,
                  title: 'შეცდომების ჟურნალი',
                  subtitle:
                      'ტექნიკური შეცდომები, კონტექსტი და დიაგნოსტიკური ინფორმაცია.',
                  badge: AdminStatusBadge(
                    icon: logs.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    label: logs.isEmpty
                        ? 'შეცდომა არ არის'
                        : '${logs.length} შეცდომა',
                    color: logs.isEmpty
                        ? AdminDesign.accentDark
                        : AdminDesign.warning,
                    background: logs.isEmpty
                        ? AdminTones.successFill
                        : AdminTones.warningFill,
                    border: logs.isEmpty
                        ? AdminTones.successBorder
                        : AdminTones.warningBorder,
                  ),
                  action: logs.isNotEmpty
                      ? OutlinedButton.icon(
                          onPressed: _confirmClearErrorLogs,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('გასუფთავება'),
                          style: AdminDesign.outlineButtonStyle(
                            foreground: AdminDesign.danger,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                if (logs.isEmpty)
                  const AdminEmptyState(
                    icon: Icons.verified_outlined,
                    title: 'ყველაფერი გამართულად მუშაობს',
                    message: 'შეცდომები ჯერ არ დაფიქსირებულა.',
                  )
                else
                  ...logs.map(_buildErrorLogCard),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorLogCard(Map<String, dynamic> log) {
    final title = (log['title'] as String?)?.trim();
    final error = (log['error'] as String?)?.trim() ?? '';
    final contextLabel = (log['context'] as String?)?.trim() ?? '';
    final performedBy = (log['performedBy'] as String?)?.trim() ?? '';
    final stackTrace = (log['stackTrace'] as String?)?.trim() ?? '';
    final metadata = log['metadata'] as Map?;
    final timestampRaw = log['timestamp'] as String? ?? '';
    final timestamp = DateTime.tryParse(timestampRaw);
    final timestampLabel = timestamp == null
        ? timestampRaw
        : DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: _borderColor),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        collapsedIconColor: _textMuted,
        iconColor: _secondaryColor,
        title: Text(
          title == null || title.isEmpty ? 'Error' : title,
          style: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          timestampLabel,
          style: const TextStyle(color: _textMuted, fontSize: 12),
        ),
        children: [
          _buildErrorLogLine('Context', contextLabel),
          _buildErrorLogLine('User', performedBy),
          _buildErrorLogLine('Error', error),
          if (metadata != null && metadata.isNotEmpty)
            _buildErrorLogLine('Metadata', metadata.toString()),
          const SizedBox(height: 12),
          const Text(
            'Stack trace',
            style: TextStyle(color: _textMuted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(AdminDesign.radius),
              border: Border.all(color: _borderColor),
            ),
            child: SelectableText(
              stackTrace.isEmpty ? '-' : stackTrace,
              style: const TextStyle(fontSize: 12, color: _textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorLogLine(String label, String value) {
    final displayValue = value.isEmpty ? '-' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              displayValue,
              style: const TextStyle(color: _textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearErrorLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          'შეცდომების გასუფთავება',
          style: TextStyle(color: _textPrimary),
        ),
        content: const Text(
          'დარწმუნებული ხართ, რომ გსურთ ყველა შეცდომის წაშლა?',
          style: TextStyle(color: _textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('გაუქმება', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminDesign.danger,
            ),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await DatabaseService.clearErrorLogs();
      setState(() {});
      unawaited(
        showPosToast(
          context: context,
          message: 'შეცდომები გასუფთავდა',
          style: PosToastStyle.info,
        ),
      );
    }
  }
}
