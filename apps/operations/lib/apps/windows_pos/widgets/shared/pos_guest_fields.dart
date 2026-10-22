import 'package:flutter/material.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';

/// The same guest controls for reservations, estimates and takeaway.
/// The workflow owns requiredness; optional contact collection stays optional.
class PosGuestFields extends StatelessWidget {
  const PosGuestFields({
    super.key,
    required this.name,
    required this.phone,
    this.optional = false,
    this.allowUnknownPhone = false,
    this.nameFocus,
    this.nameError,
  });
  final TextEditingController name;
  final TextEditingController phone;
  final bool optional;
  final bool allowUnknownPhone;
  final FocusNode? nameFocus;
  final String? nameError;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PosOnScreenTextField(
        controller: name,
        focusNode: nameFocus,
        decoration: InputDecoration(
          labelText: optional
              ? 'სახელი და გვარი (არასავალდებულო)'
              : 'სტუმრის სახელი',
          hintText: 'სახელი და გვარი',
          prefixIcon: const Icon(Icons.person_outline),
          errorText: nameError,
        ),
      ),
      const SizedBox(height: 16),
      PosOnScreenTextField(
        controller: phone,
        mode: PosInputMode.number,
        allowQuestionMark: allowUnknownPhone,
        decoration: InputDecoration(
          labelText: optional ? 'ტელეფონი (არასავალდებულო)' : 'ტელეფონი',
          hintText: 'ტელეფონი',
          prefixIcon: const Icon(Icons.phone_outlined),
        ),
      ),
    ],
  );
}
