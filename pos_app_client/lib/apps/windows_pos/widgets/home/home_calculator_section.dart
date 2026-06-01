import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/models/quick_order_draft.dart';
import 'package:vynic/apps/windows_pos/widgets/home/home_quick_order_draft_card.dart';

class HomeCalculatorSection extends StatelessWidget {
  const HomeCalculatorSection({
    super.key,
    required this.quickOrderDrafts,
    required this.onStartQuickOrder,
    required this.onToggleServiceFee,
    required this.onOpenServiceFeeConfig,
    required this.onContinueDraft,
    required this.onPrintDraft,
    required this.canManageDrafts,
    required this.onOpenDraftManage,
    required this.onClearAllDrafts,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textPrimary,
    required this.mutedText,
    this.hideTitle = false,
  });

  final List<QuickOrderDraft> quickOrderDrafts;
  final VoidCallback onStartQuickOrder;
  final ValueChanged<QuickOrderDraft> onToggleServiceFee;
  final ValueChanged<QuickOrderDraft> onOpenServiceFeeConfig;
  final ValueChanged<QuickOrderDraft> onContinueDraft;
  final ValueChanged<QuickOrderDraft> onPrintDraft;
  final bool canManageDrafts;
  final ValueChanged<QuickOrderDraft> onOpenDraftManage;
  final VoidCallback onClearAllDrafts;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textPrimary;
  final Color mutedText;
  final bool hideTitle;

  @override
  Widget build(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 24, 
        isMobile ? 16 : 24, 
        isMobile ? 16 : 24, 
        96,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hideTitle)
            _buildSectionTitle(
              icon: Icons.calculate_outlined,
              title: 'მენიუს დათვლა',
              subtitle:
                  'გამოიყენე სწრაფი კალკულატორი შეკვეთების დასათვლელად მაგიდის გარეშე.',
              isMobile: isMobile,
            ),
          if (!hideTitle) SizedBox(height: isMobile ? 16 : 20),
          _buildActionCard(
            icon: Icons.functions_outlined,
            title: 'სწრაფი კალკულატორი',
            description:
                'დაადგინე შეკვეთის ჯამი, კომბოები ან ფასდაკლებები რამდენიმე წამში.',
            isMobile: isMobile,
            actions: [
              ElevatedButton.icon(
                onPressed: onStartQuickOrder,
                icon: const Icon(Icons.open_in_new, size: 20),
                label: const Text('დაწყება'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'დათვლილი მენიუები',
            style: TextStyle(
              color: textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (quickOrderDrafts.isNotEmpty && canManageDrafts)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onClearAllDrafts,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    backgroundColor: const Color(0xFFFFF1F2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('ყველას წაშლა'),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (quickOrderDrafts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primaryColor.withValues(alpha: 0.08)),
              ),
              child: Text(
                'შენახული მენიუები ჯერ არ არსებობს.',
                style: TextStyle(color: mutedText),
              ),
            )
          else
            Column(
              children: quickOrderDrafts
                  .map(
                    (draft) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: HomeQuickOrderDraftCard(
                        draft: draft,
                        onToggleServiceFee: () => onToggleServiceFee(draft),
                        onOpenServiceFeeConfig: () =>
                            onOpenServiceFeeConfig(draft),
                        onContinue: () => onContinueDraft(draft),
                        onPrint: () => onPrintDraft(draft),
                        canManage: canManageDrafts,
                        onOpenManage: () => onOpenDraftManage(draft),
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor,
                        textPrimary: textPrimary,
                        mutedText: mutedText,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool isMobile,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: primaryColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: mutedText, fontSize: isMobile ? 13 : 14),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> actions,
    required bool isMobile,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: secondaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: secondaryColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(color: mutedText, fontSize: isMobile ? 13 : 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ),
    );
  }
}
