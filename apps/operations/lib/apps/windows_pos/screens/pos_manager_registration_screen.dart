import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:vynic/core/services/auth/manager_activation_service.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';

/// First Manager registration belongs to the enrolled POS; no PIN is persisted here.
class PosManagerRegistrationScreen extends StatefulWidget {
  const PosManagerRegistrationScreen({super.key, this.client, this.setupId});
  final http.Client? client;
  final String? setupId;
  @override
  State<PosManagerRegistrationScreen> createState() =>
      _PosManagerRegistrationScreenState();
}

class _PosManagerRegistrationScreenState
    extends State<PosManagerRegistrationScreen> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  final _requestId = const Uuid().v4();
  bool _busy = false;
  bool _completed = false;
  String? _error;
  InputDecoration _decoration(
    String label,
    TextEditingController controller, {
    bool pin = false,
    String? helperText,
  }) => InputDecoration(
    labelText: label,
    helperText: helperText,
    suffixIcon: IconButton(
      tooltip: '$label — ეკრანის კლავიატურა',
      icon: const Icon(Icons.keyboard),
      onPressed: _busy
          ? null
          : () async {
              FocusScope.of(context).unfocus();
              if (pin) {
                await showPosNumberKeyboardInputSheet(
                  context: context,
                  initialValue: controller.text,
                  controller: controller,
                  title: label,
                  pin: true,
                  maxDigits: 6,
                );
              } else {
                await showPosKeyboardInputSheet(
                  context: context,
                  controller: controller,
                  title: label,
                  followLocale: false,
                  initialLanguage: controller == _name
                      ? PosKeyboardLanguage.georgian
                      : PosKeyboardLanguage.english,
                );
              }
            },
    ),
  );
  @override
  void dispose() {
    for (final c in [_code, _name, _pin, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await PosManagerRegistrationService.complete(
        code: _code.text,
        name: _name.text,
        pin: _pin.text,
        requestId: widget.setupId ?? _requestId,
        setupId: widget.setupId,
        client: widget.client,
      );
      if (!mounted) return;
      _pin.clear();
      _confirm.clear();
      _code.clear();
      setState(() => _completed = true);
    } on ActivationFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.setupId == null
            ? 'პირველი აქტივაცია'
            : 'პირველი Manager-ის შექმნა',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _completed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'აქტივაცია დასრულდა',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'დატოვეთ POS ინტერნეტთან დაკავშირებული. წვდომის მიღების შემდეგ შედით თქვენი ახალი PIN-ით. შემდეგ ამავე PIN-ით შეძლებთ Manager აპში შესვლას.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('შესვლაზე დაბრუნება'),
                      ),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.setupId == null
                              ? 'შეიყვანეთ კაბინეტში ან Vynic Admin-ისგან მიღებული ერთჯერადი კოდი. აირჩიეთ თქვენი სახელი და პირადი PIN.'
                              : 'რესტორანი უკვე დაკავშირებულია. აირჩიეთ თქვენი სახელი და პირადი PIN.',
                        ),
                        const SizedBox(height: 20),
                        if (widget.setupId == null)
                          TextFormField(
                            controller: _code,
                            enabled: !_busy,
                            autocorrect: false,
                            enableSuggestions: false,
                            obscureText: true,
                            decoration: _decoration('აქტივაციის კოდი', _code),
                            validator: _required,
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          maxLength: 80,
                          decoration: _decoration('თქვენი სახელი', _name),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pin,
                          enabled: !_busy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: _decoration(
                            'ახალი PIN',
                            _pin,
                            pin: true,
                            helperText: '4–6 ციფრი',
                          ),
                          validator: (v) =>
                              RegExp(r'^\d{4,6}$').hasMatch(v ?? '')
                              ? null
                              : 'შეიყვანეთ 4–6 ციფრი',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: _decoration(
                            'გაიმეორეთ PIN',
                            _confirm,
                            pin: true,
                          ),
                          validator: (v) =>
                              v == _pin.text ? null : 'PIN არ ემთხვევა',
                        ),
                        const SizedBox(height: 20),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(_busy ? 'მუშავდება…' : 'აქტივაცია'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'შეავსეთ ველი' : null;
}
