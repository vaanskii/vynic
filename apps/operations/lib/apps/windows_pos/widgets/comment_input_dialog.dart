import 'package:flutter/material.dart';
import 'package:vynic/core/ui/widgets/pos_dialog.dart';
import 'package:vynic/core/widgets/pos_on_screen_text_field.dart';
import 'package:vynic/core/widgets/pos_text.dart';

class CommentInputDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String? subtitle;
  final String? initialComment;
  final bool _required;
  final bool _allowDelete;
  final String _submitLabel;

  const CommentInputDialog({
    super.key,
    required this.title,
    this.hint = 'შეიყვანეთ კომენტარი...',
  }) : subtitle = null,
       initialComment = null,
       _required = true,
       _allowDelete = false,
       _submitLabel = 'დადასტურება';

  /// Menu comments preserve the existing null/empty distinction: null leaves
  /// the item alone, and only the explicit Delete action returns an empty value.
  const CommentInputDialog.menuItem({
    super.key,
    required String itemName,
    this.initialComment,
  }) : title = 'კომენტარი',
       subtitle = itemName,
       hint = 'მაგალითად: ხახვის გარეშე, ცხარე...',
       _required = false,
       _allowDelete = true,
       _submitLabel = 'შენახვა';

  @override
  State<CommentInputDialog> createState() => _CommentInputDialogState();
}

class _CommentInputDialogState extends State<CommentInputDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialComment ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.of(context).pop(_controller.text.trim());
    } else if (widget._required) {
      setState(() => _error = 'გთხოვთ შეიყვანოთ კომენტარი');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => PosFormDialog(
    title: widget.title,
    subtitle: widget.subtitle,
    onClose: () => Navigator.pop(context),
    actions: [
      if (widget._allowDelete && (widget.initialComment?.isNotEmpty ?? false))
        TextButton.icon(
          onPressed: () => Navigator.pop(context, ''),
          icon: const Icon(Icons.delete_outline),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          label: const PosText('წაშლა'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const PosText('გაუქმება'),
      ),
      ElevatedButton(onPressed: _submit, child: PosText(widget._submitLabel)),
    ],
    child: PosOnScreenTextField(
      controller: _controller,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: widget.title,
        hintText: widget.hint,
        errorText: _error,
      ),
    ),
  );
}
