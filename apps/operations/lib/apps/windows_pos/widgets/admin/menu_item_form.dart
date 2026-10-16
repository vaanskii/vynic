import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/core/models/menu_item_db.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/widgets/pos_text.dart';

typedef SaveMenuItem =
    Future<bool> Function(
      String nameEn,
      String nameKa,
      double? price,
      List<MenuVariantDB>? variants,
      bool sendToKitchen,
    );

/// Category and subcategory creation/editing share exactly the same fields and
/// validation. The owner selects the existing repository mutation.
class MenuItemForm extends StatefulWidget {
  const MenuItemForm({
    super.key,
    this.item,
    required this.defaultSendToKitchen,
    required this.onSave,
    required this.onAddVariant,
  });
  final MenuItemDB? item;
  final bool defaultSendToKitchen;
  final SaveMenuItem onSave;
  final void Function(BuildContext, ValueChanged<MenuVariantDB>) onAddVariant;
  @override
  State<MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends State<MenuItemForm> {
  late final nameEn = TextEditingController(
    text: widget.item?.translationsEn['name'] ?? '',
  );
  late final nameKa = TextEditingController(
    text: widget.item?.translationsKa['name'] ?? '',
  );
  late final price = TextEditingController(
    text: widget.item?.price?.toString() ?? '',
  );
  late final List<MenuVariantDB> variants = List.of(
    widget.item?.variants ?? [],
  );
  late bool hasVariants = variants.isNotEmpty;
  late bool kitchen = widget.item?.sendToKitchen ?? widget.defaultSendToKitchen;
  bool saving = false;
  String? error;

  void stepPrice(double delta) {
    final current = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    final next = current + delta;
    price.text = (next < 0 ? 0 : next).toStringAsFixed(2);
    price.selection = TextSelection.collapsed(offset: price.text.length);
  }

  @override
  void dispose() {
    nameEn.dispose();
    nameKa.dispose();
    price.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    // Retain the existing admission rule and values (including optional price).
    if (nameEn.text.isEmpty || nameKa.text.isEmpty) {
      setState(() => error = 'შეიყვანეთ სახელი ორივე ენაზე');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await widget.onSave(
        nameEn.text,
        nameKa.text,
        hasVariants ? null : double.tryParse(price.text),
        hasVariants && variants.isNotEmpty ? List.of(variants) : null,
        kitchen,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => error = 'პროდუქტი ვერ შეინახა');
    } catch (failure) {
      if (mounted) setState(() => error = 'პროდუქტი ვერ შეინახა: $failure');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: PosFormDialog(
      title: widget.item == null ? 'ახალი პროდუქტი' : 'პროდუქტის რედაქტირება',
      onClose: saving ? null : () => Navigator.pop(context),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const PosText('გაუქმება'),
        ),
        ElevatedButton(
          onPressed: saving ? null : save,
          child: PosText(widget.item == null ? 'დამატება' : 'განახლება'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            PosFormError(error!),
            const SizedBox(height: 16),
          ],
          PosOnScreenTextField(
            controller: nameEn,
            keyboardLanguage: 'en',
            enabled: !saving,
            decoration: const InputDecoration(labelText: 'სახელი (ინგლისური)'),
          ),
          const SizedBox(height: 16),
          PosOnScreenTextField(
            controller: nameKa,
            keyboardLanguage: 'ka',
            enabled: !saving,
            decoration: const InputDecoration(labelText: 'სახელი (ქართული)'),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const PosText('პროდუქტი იგზავნება სამზარეულოში'),
            value: kitchen,
            onChanged: saving ? null : (v) => setState(() => kitchen = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const PosText('აქვს ვარიანტები?'),
            value: hasVariants,
            onChanged: saving
                ? null
                : (v) => setState(() {
                    hasVariants = v;
                    if (!v) variants.clear();
                  }),
          ),
          const SizedBox(height: 16),
          if (!hasVariants)
            Row(
              children: [
                IconButton(
                  tooltip: '−0.50 ₾',
                  onPressed: saving ? null : () => stepPrice(-.5),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(
                  child: PosOnScreenTextField(
                    controller: price,
                    mode: PosInputMode.decimal,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}$'),
                      ),
                    ],
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: 'ფასი (₾)'),
                  ),
                ),
                IconButton(
                  tooltip: '+0.50 ₾',
                  onPressed: saving ? null : () => stepPrice(.5),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            )
          else ...[
            for (var i = 0; i < variants.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${variants[i].size}ml - ₾${variants[i].price.toStringAsFixed(2)}',
                ),
                trailing: IconButton(
                  tooltip: 'წაშლა',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: saving
                      ? null
                      : () => setState(() => variants.removeAt(i)),
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const PosText('ვარიანტის დამატება'),
              onPressed: saving
                  ? null
                  : () => widget.onAddVariant(context, (v) {
                      if (mounted) setState(() => variants.add(v));
                    }),
            ),
          ],
        ],
      ),
    ),
  );
}
