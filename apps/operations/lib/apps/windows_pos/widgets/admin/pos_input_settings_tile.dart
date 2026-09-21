import 'package:vynic/core/widgets/pos_text.dart';
import 'package:flutter/material.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';

class PosInputSettingsTile extends StatefulWidget {
  const PosInputSettingsTile({super.key});
  @override
  State<PosInputSettingsTile> createState() => _PosInputSettingsTileState();
}

class _PosInputSettingsTileState extends State<PosInputSettingsTile> {
  bool _saving = false;
  Future<void> _save(bool value) async {
    setState(() => _saving = true);
    try {
      await PosInputSettings.save(value);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: PosText(
              'პარამეტრის შენახვა ვერ მოხერხდა. სცადეთ ხელახლა.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: PosInputSettings.enabled,
    builder: (context, enabled, _) => SwitchListTile.adaptive(
      title: const PosText('ეკრანის კლავიატურა'),
      subtitle: const PosText(
        'ტექსტისა და რიცხვების შეყვანა ამ POS-ზე. შესვლისა და ჩაკეტვის PIN პანელი ყოველთვის ხელმისაწვდომია.',
      ),
      secondary: _saving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.keyboard_outlined),
      value: enabled,
      onChanged: _saving ? null : _save,
    ),
  );
}
