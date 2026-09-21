import 'package:flutter/material.dart';
import '../../../../core/services/manager_app/manager_entitlements.dart';
import '../../../../core/services/manager_app/mobile_api_service.dart';

class VenueProfileCard extends StatelessWidget {
  const VenueProfileCard({super.key});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: ManagerEntitlements.profile,
        builder: (context, profile, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'რესტორნის პროფილი',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (profile == null)
                  const Text('პროფილი ჯერ არ ჩატვირთულა. გადაამოწმეთ კავშირი.')
                else ...[
                  for (final field in _fields)
                    if ((profile[field.key] as String? ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('${field.label}: ${profile[field.key]}'),
                      ),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('პროფილის შეცვლა'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ProfileEditor(profile: profile),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

const _fields = <({String key, String label, int max})>[
  (key: 'name', label: 'რესტორნის სახელი', max: 100),
  (key: 'branchName', label: 'ფილიალის სახელი', max: 100),
  (key: 'address', label: 'მისამართი', max: 300),
  (key: 'phone', label: 'ტელეფონი', max: 50),
  (key: 'legalId', label: 'საიდენტიფიკაციო ნომერი', max: 50),
];

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.profile});
  final Map<String, dynamic> profile;
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _controllers = {
    for (final f in _fields)
      f.key: TextEditingController(
        text: widget.profile[f.key] as String? ?? '',
      ),
  };
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MobileApiService.saveVenueProfile({
        for (final f in _fields) f.key: _controllers[f.key]!.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted)
        setState(
          () => _error =
              'პროფილი ვერ შეინახა. გადაამოწმეთ კავშირი და სცადეთ ხელახლა.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('რესტორნის პროფილი'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in _fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _controllers[f.key],
                    enabled: !_busy,
                    maxLength: f.max,
                    decoration: InputDecoration(
                      labelText: f.label,
                      helperText: f.key == 'name' ? null : 'არასავალდებულო',
                    ),
                    validator: (value) =>
                        f.key == 'name' && (value?.trim().isEmpty ?? true)
                        ? 'შეიყვანეთ სახელი'
                        : null,
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('გაუქმება'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'ინახება…' : 'შენახვა'),
      ),
    ],
  );
}
