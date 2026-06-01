import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/pos_feedback.dart';

class AdminErrorLogSection extends StatefulWidget {
  const AdminErrorLogSection({super.key});

  @override
  State<AdminErrorLogSection> createState() => _AdminErrorLogSectionState();
}

class _AdminErrorLogSectionState extends State<AdminErrorLogSection> {
  static const Color _secondaryColor = Color(0xFF2563EB);
  static const Color _surfaceColor = Color(0xFFF4F6FF);
  static const Color _cardColor = Colors.white;
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final logs = DatabaseService.getErrorLogs();

    return SizedBox.expand(
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'შეცდომები',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (logs.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: _confirmClearErrorLogs,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('გასუფთავება'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (logs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _borderColor),
                    ),
                    child: const Text(
                      'შეცდომები ჯერ არ დაფიქსირებულა.',
                      style: TextStyle(color: _textMuted, fontSize: 14),
                    ),
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
        borderRadius: BorderRadius.circular(16),
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
              borderRadius: BorderRadius.circular(12),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
