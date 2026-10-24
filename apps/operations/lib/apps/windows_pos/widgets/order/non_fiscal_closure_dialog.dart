import 'package:flutter/material.dart';
import 'package:vynic/core/database/repositories/inventory_repository.dart';
import 'package:vynic/core/models/feature_keys.dart';

/// The route reacts to revocation independently of the screen underneath it.
class NonFiscalClosureDialog extends StatelessWidget {
  const NonFiscalClosureDialog({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: InventoryRepository.featureRevision,
    builder: (context, _, child) {
      final enabled = InventoryRepository.hasFeature(
        FeatureKeys.nonFiscalClose,
      );
      return AlertDialog(
        title: Text(enabled ? 'არაფისკალური დახურვა' : 'ოპერაცია მიუწვდომელია'),
        constraints: const BoxConstraints(maxWidth: 560),
        scrollable: true,
        content: enabled
            ? const Text(
                'დახურეთ მაგიდა არაფისკალურად. ეს ოპერაცია არ გამოჩნდება Z რეპორტში, მაგრამ ჩაიწერება გაყიდვების ისტორიაში.',
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(enabled ? 'გაუქმება' : 'დახურვა'),
          ),
          if (enabled)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('დახურვა და დაფიქსირება'),
            ),
        ],
      );
    },
  );
}
