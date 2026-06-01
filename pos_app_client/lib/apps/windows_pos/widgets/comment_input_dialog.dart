import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'on_screen_keyboard.dart';

class CommentInputDialog extends StatefulWidget {
  final String title;
  final String hint;

  const CommentInputDialog({
    super.key,
    required this.title,
    this.hint = 'შეიყვანეთ კომენტარი...',
  });

  @override
  State<CommentInputDialog> createState() => _CommentInputDialogState();
}

class _CommentInputDialogState extends State<CommentInputDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _showKeyboard = false;
  String _currentLanguage = 'ka'; // Default to Georgian

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.of(context).pop(_controller.text.trim());
    } else {
      unawaited(
        showPosToast(
          context: context,
          message: 'გთხოვთ შეიყვანოთ კომენტარი',
          style: PosToastStyle.info,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Main dialog content
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B2B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.comment_outlined,
                      color: Color(0xFFC0AD7B),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Text field
                TextField(
                  controller: _controller,
                  readOnly: true,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1a1a1a),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF444444)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF444444)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFC0AD7B),
                        width: 2,
                      ),
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _showKeyboard = true;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'გაუქმება',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC0AD7B),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'დადასტურება',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Keyboard
          if (_showKeyboard)
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1a1a1a),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Language toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentLanguage == 'ka' ? 'ქართული' : 'English',
                          style: const TextStyle(
                            color: Color(0xFFC0AD7B),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _currentLanguage = _currentLanguage == 'ka'
                                      ? 'en'
                                      : 'ka';
                                });
                              },
                              child: const Icon(
                                Icons.language,
                                color: Color(0xFFC0AD7B),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _showKeyboard = false;
                                });
                              },
                              child: const Icon(
                                Icons.keyboard_hide,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  OnScreenKeyboard(
                    controller: _controller,
                    language: _currentLanguage,
                    onClose: () {
                      setState(() {
                        _showKeyboard = false;
                      });
                    },
                    onEnter: _submit,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
