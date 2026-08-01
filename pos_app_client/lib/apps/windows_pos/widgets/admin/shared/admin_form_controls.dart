import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';

/// Text field used by the admin forms. Tapping it opens the POS on-screen
/// keyboard (alphanumeric or numeric) rather than the platform keyboard.
///
/// Lifted verbatim out of `AdminSettingsSection._buildSettingsTextField` when
/// the report blocks moved to their own section; both callers share it now.
class AdminPosTextField extends StatelessWidget {
  const AdminPosTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final usesNumberKeyboard =
        keyboardType.index == TextInputType.number.index ||
        keyboardType == TextInputType.phone;
    final allowsDecimal =
        keyboardType.index == TextInputType.number.index &&
        keyboardType.decimal == true;

    return TextField(
      controller: controller,
      enabled: enabled,
      readOnly: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(color: AdminDesign.text),
      onChanged: onChanged,
      onTap: !enabled
          ? null
          : () async {
              String? updated;
              if (usesNumberKeyboard) {
                updated = await showPosNumberKeyboardInputSheet(
                  context: context,
                  initialValue: controller.text,
                  title: label,
                  allowDecimal: allowsDecimal,
                );
              } else {
                updated = await showPosKeyboardInputSheet(
                  context: context,
                  controller: controller,
                  initialLanguage: PosKeyboardLanguage.georgian,
                  title: label,
                );
              }

              if (updated == null) return;
              if (controller.text != updated) {
                controller.value = TextEditingValue(
                  text: updated,
                  selection: TextSelection.collapsed(offset: updated.length),
                );
              }
              onChanged?.call(controller.text);
            },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AdminDesign.muted),
        hintStyle: TextStyle(color: AdminDesign.muted.withValues(alpha: 0.6)),
        suffixIcon: enabled
            ? Icon(
                usesNumberKeyboard
                    ? Icons.dialpad_outlined
                    : Icons.keyboard_alt_outlined,
                color: AdminDesign.accentDark,
                size: 20,
              )
            : null,
        filled: true,
        fillColor: enabled ? AdminDesign.panelSoft : AdminDesign.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminDesign.radius),
          borderSide: const BorderSide(color: AdminDesign.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminDesign.radius),
          borderSide: const BorderSide(color: AdminDesign.accentDark, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AdminDesign.radius),
          borderSide: BorderSide(
            color: AdminDesign.border.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// Tinted strip that holds a card's save / generate buttons.
class AdminActionRow extends StatelessWidget {
  const AdminActionRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminDesign.panelSoft,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: AdminDesign.border),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: children,
      ),
    );
  }
}

/// Button styles the settings/report cards use. These differ from
/// [AdminDesign.primaryButtonStyle] only in padding, which is why they live
/// here rather than being folded into the shared design tokens.
abstract final class AdminFormButtons {
  static ButtonStyle primary() {
    return ElevatedButton.styleFrom(
      backgroundColor: AdminDesign.accentDark,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
      ),
      elevation: 0,
    );
  }

  static ButtonStyle outline() {
    return OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      side: const BorderSide(color: AdminDesign.border, width: 1.4),
      foregroundColor: AdminDesign.text,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.radius),
      ),
    );
  }
}
