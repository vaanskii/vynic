import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/services/security/developer_access.dart';

/// Unlock prompt for the developer half of the admin panel.
///
/// Deliberately plain and English-only: the venue's staff are not the audience,
/// and a screen that looks like part of the product invites someone to try
/// PINs against it.
class DeveloperUnlockDialog extends StatefulWidget {
  const DeveloperUnlockDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DeveloperUnlockDialog(),
    );
    return result ?? false;
  }

  @override
  State<DeveloperUnlockDialog> createState() => _DeveloperUnlockDialogState();
}

class _DeveloperUnlockDialogState extends State<DeveloperUnlockDialog> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  String? _error;
  bool _isVerifying = false;

  /// The short code is the everyday path — sixteen characters somebody can
  /// read down a phone. The signed token stays for the cases a code cannot
  /// cover: a terminal whose chain has run out, or one that needs a session
  /// longer than a support call.
  bool _showSignedToken = false;

  /// Wrong tokens get slower to try. A signature cannot be brute-forced in any
  /// case, but this removes the temptation to sit and poke at the field.
  int _failedAttempts = 0;
  DateTime? _lockedOutUntil;

  @override
  void initState() {
    super.initState();
    // The id shown here is what a token gets signed against, so it has to
    // survive a restart before anyone reads it out.
    unawaited(DeveloperAccess.persistTerminalId());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Duration get _remainingLockout {
    final until = _lockedOutUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _verifyCode() => _attempt(
    () => DeveloperAccess.unlockWithOneTimeCode(_codeController.text),
  );

  Future<void> _verify() =>
      _attempt(() => DeveloperAccess.unlock(_tokenController.text));

  Future<void> _attempt(Future<DeveloperUnlockResult> Function() unlock) async {
    if (_remainingLockout > Duration.zero) {
      setState(() {
        _error = 'Too many attempts. Wait ${_remainingLockout.inSeconds}s.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final result = await unlock();
    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
      return;
    }

    _failedAttempts++;
    if (_failedAttempts >= 3) {
      _lockedOutUntil = DateTime.now().add(
        Duration(seconds: 15 * (_failedAttempts - 2)),
      );
    }

    setState(() {
      _isVerifying = false;
      _error = _messageFor(result.failure!);
    });
  }

  String _messageFor(DeveloperUnlockFailure failure) {
    switch (failure) {
      case DeveloperUnlockFailure.malformed:
        return 'Not a valid token. Paste the whole line, including the dot.';
      case DeveloperUnlockFailure.badSignature:
        return 'Signature rejected. This token was not signed by the Vynic key.';
      case DeveloperUnlockFailure.wrongTerminal:
        return 'Token is bound to a different terminal. Sign one for '
            '${DeveloperAccess.terminalIdShort}.';
      case DeveloperUnlockFailure.expired:
        return 'Token has expired. Sign a fresh one.';
      case DeveloperUnlockFailure.notYetValid:
        return 'Token is dated in the future — check this machine\'s clock.';
      case DeveloperUnlockFailure.badCode:
        return 'That is not a sixteen-character code.';
      case DeveloperUnlockFailure.spentCode:
        return 'Code rejected. It has already been used on this terminal, or '
            'it came from a different build. Try the next one.';
    }
  }

  Future<void> _loadFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select unlock token file',
      type: FileType.any,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    try {
      final contents = await File(path).readAsString();
      if (!mounted) return;
      _tokenController.text = contents.trim();
      await _verify();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not read that file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final terminalId = DeveloperAccess.terminalId;

    return Dialog(
      backgroundColor: AdminDesign.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminDesign.panelRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.engineering_outlined,
                    color: AdminDesign.accentDark,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Developer access',
                      style: TextStyle(
                        color: AdminDesign.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: AdminDesign.muted),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _showSignedToken
                    ? 'Paste a signed unlock token, or load one from a file. A '
                          'master token works on any terminal and needs no ID.'
                    : 'Type the one-time code. It works once, then it is dead.',
                style: const TextStyle(color: AdminDesign.muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              if (_showSignedToken) ...[
                _buildTerminalIdRow(terminalId),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 3,
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Unlock token',
                    hintText: 'eyJ2Ijox….<signature>',
                    filled: true,
                    fillColor: AdminDesign.panelSoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AdminDesign.radius),
                    ),
                  ),
                  onSubmitted: (_) => _verify(),
                ),
              ] else
                TextField(
                  controller: _codeController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontFamily: 'monospace',
                    fontSize: 20,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'One-time code',
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    filled: true,
                    fillColor: AdminDesign.panelSoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AdminDesign.radius),
                    ),
                  ),
                  inputFormatters: [_OneTimeCodeFormatter()],
                  onSubmitted: (_) => _verifyCode(),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminDesign.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AdminDesign.radius),
                    border: Border.all(
                      color: AdminDesign.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AdminDesign.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  if (_showSignedToken)
                    OutlinedButton.icon(
                      onPressed: _isVerifying ? null : _loadFromFile,
                      style: AdminDesign.outlineButtonStyle(),
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Load from file'),
                    ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _isVerifying
                        ? null
                        : (_showSignedToken ? _verify : _verifyCode),
                    style: AdminDesign.primaryButtonStyle(),
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open, size: 18),
                    label: Text(_isVerifying ? 'Verifying…' : 'Unlock'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isVerifying
                      ? null
                      : () => setState(() {
                          _showSignedToken = !_showSignedToken;
                          _error = null;
                        }),
                  icon: Icon(
                    _showSignedToken ? Icons.pin : Icons.verified_user,
                    size: 16,
                    color: AdminDesign.muted,
                  ),
                  label: Text(
                    _showSignedToken
                        ? 'Use a one-time code instead'
                        : 'Use a signed token instead',
                    style: const TextStyle(
                      color: AdminDesign.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalIdRow(String terminalId) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminDesign.panelSoft,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(color: AdminDesign.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Terminal ID',
                  style: TextStyle(
                    color: AdminDesign.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  terminalId,
                  style: const TextStyle(
                    color: AdminDesign.text,
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: terminalId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Terminal ID copied')),
              );
            },
            icon: const Icon(Icons.copy, size: 18, color: AdminDesign.muted),
          ),
        ],
      ),
    );
  }
}

/// Formats the code as it is typed: upper case, dashes every four characters,
/// and nothing past sixteen. Somebody reading a code aloud will include the
/// dashes or not, and the field should not care either way.
class _OneTimeCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final stripped = newValue.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    final capped = stripped.length > 16 ? stripped.substring(0, 16) : stripped;

    final grouped = <String>[
      for (var i = 0; i < capped.length; i += 4)
        capped.substring(i, i + 4 > capped.length ? capped.length : i + 4),
    ].join('-');

    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}
