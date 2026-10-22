import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:flutter/material.dart';
import 'shared/pos_guest_fields.dart';

class EstimateCustomerDetails {
  const EstimateCustomerDetails(this.name, this.phone);
  final String name;
  final String phone;
}

/// Optional contacts are collected before persistence; dismissing keeps the cart.
class EstimateCustomerDialog extends StatefulWidget {
  const EstimateCustomerDialog({super.key, this.name, this.phone});
  final String? name;
  final String? phone;

  static Future<EstimateCustomerDetails?> show(
    BuildContext context, {
    String? name,
    String? phone,
  }) => showPosModal<EstimateCustomerDetails>(
    context: context,
    builder: (_) => EstimateCustomerDialog(name: name, phone: phone),
  );

  @override
  State<EstimateCustomerDialog> createState() => _EstimateCustomerDialogState();
}

class _EstimateCustomerDialogState extends State<EstimateCustomerDialog> {
  late final name = TextEditingController(text: widget.name ?? '');
  late final phone = TextEditingController(text: widget.phone ?? '');

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    width: 460,
    title: 'შეფასების შენახვა',
    onClose: () => Navigator.pop(context),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('უკან'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          EstimateCustomerDetails(name.text.trim(), phone.text.trim()),
        ),
        child: const Text('შენახვა'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'სახელი და ტელეფონი არასავალდებულოა. მათი დამატებით შეფასებას უფრო ადვილად იპოვით.',
        ),
        const SizedBox(height: 24),
        PosGuestFields(name: name, phone: phone, optional: true),
      ],
    ),
  );
}
