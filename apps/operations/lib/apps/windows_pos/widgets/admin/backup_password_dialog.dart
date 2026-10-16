import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

class BackupPasswordDialog extends StatefulWidget {
  const BackupPasswordDialog({super.key, required this.creating});
  final bool creating;
  static Future<String?> show(BuildContext context, {required bool creating}) =>
      showPosModal<String>(
        context: context,
        builder: (_) => BackupPasswordDialog(creating: creating),
      );
  @override
  State<BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<BackupPasswordDialog> {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  String? error;
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  void submit() {
    if (password.text.isEmpty ||
        (widget.creating && password.text.length < 12)) {
      setState(() => error = 'პაროლი უნდა შეიცავდეს მინიმუმ 12 სიმბოლოს.');
      return;
    }
    if (widget.creating && password.text != confirmation.text) {
      setState(() => error = 'პაროლები არ ემთხვევა.');
      return;
    }
    Navigator.pop(context, password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AdminDesign.panel,
    title: Text(
      widget.creating
          ? 'სარეზერვო ასლის პაროლი'
          : 'შეიყვანეთ სარეზერვო ასლის პაროლი',
    ),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.creating
                  ? 'ასლი შეიცავს თანამშრომლების PIN-ებს და სტუმრების მონაცემებს. შეინახეთ პაროლი ასლისგან განცალკევებით. პაროლის დაკარგვისას დაშიფრული ასლის აღდგენა შეუძლებელია.'
                  : 'აღდგენისთვის საჭიროა ასლის შექმნისას გამოყენებული პაროლი.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('backup-password'),
              controller: password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'პაროლი'),
            ),
            if (widget.creating)
              TextField(
                key: const Key('backup-password-confirm'),
                controller: confirmation,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'გაიმეორეთ პაროლი',
                ),
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('გაუქმება'),
      ),
      FilledButton(
        key: const Key('backup-password-submit'),
        onPressed: submit,
        child: const Text('გაგრძელება'),
      ),
    ],
  );
}
