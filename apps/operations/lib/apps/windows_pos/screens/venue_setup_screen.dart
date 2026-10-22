import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/venue_identity_draft.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/venue_identity_panel.dart';
import 'package:vynic/core/services/pos/pos_input_settings.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';

/// The one screen a terminal shows before it has ever been used.
///
/// Collect restaurant identity and this terminal's input preference after login.
/// Completion is persisted last so interrupted saves can be safely retried.
class VenueSetupScreen extends StatefulWidget {
  const VenueSetupScreen({super.key, required this.onCompleted});

  /// Called once the name is saved and setup is marked done.
  final VoidCallback onCompleted;

  @override
  State<VenueSetupScreen> createState() => _VenueSetupScreenState();
}

class _VenueSetupScreenState extends State<VenueSetupScreen> {
  final VenueIdentityDraft _draft = VenueIdentityDraft();
  bool _saving = false;
  late bool _touchInput;
  String? _error;

  @override
  void initState() {
    super.initState();
    _touchInput = SettingsRepository.getPosOnScreenInputEnabled();
    _draft.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraftChanged);
    _draft.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  /// „Start" is the save button here. A first-time user should not have to
  /// press two, and there is nothing on this screen worth keeping unsaved.
  Future<void> _finish() async {
    if (_saving || !_draft.hasName) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _draft.save();
      await PosInputSettings.save(_touchInput);
      await DatabaseService.markSetupComplete();
    } catch (error, stack) {
      debugPrint('Venue setup save failed: $error\n$stack');
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'შენახვა ვერ მოხერხდა. სცადეთ ხელახლა.';
        });
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final named = _draft.hasName;

    return Scaffold(
      backgroundColor: VynicFloorTokens.page,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: PosPanel(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PosSectionLabel('პირველი გაშვება'),
                  const SizedBox(height: 8),
                  const Text(
                    'მოგესალმებით',
                    style: TextStyle(
                      color: VynicFloorTokens.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'შეამოწმეთ რესტორნის მონაცემები და აირჩიეთ შეყვანის გზა. '
                    'მისამართი და ტელეფონი სურვილისამებრ შეგიძლიათ დაამატოთ. '
                    'არჩევანის შეცვლა მოგვიანებითაც შეგიძლიათ პარამეტრებიდან.',
                    style: TextStyle(
                      color: VynicFloorTokens.textMuted,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // The same panel the admin panel uses, so changing the name
                  // later looks like the place it was first entered.
                  VenueIdentityPanel(
                    draft: _draft,
                    showAddressAndPhone: true,
                    showSaveButton: false,
                    showLogo: false,
                  ),
                  const SizedBox(height: 20),
                  const Text('როგორ იყენებთ POS-ს?'),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('სენსორული ეკრანი'),
                        icon: Icon(Icons.touch_app),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('კლავიატურა'),
                        icon: Icon(Icons.keyboard),
                      ),
                    ],
                    selected: {_touchInput},
                    onSelectionChanged: _saving
                        ? null
                        : (values) =>
                              setState(() => _touchInput = values.single),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  PosPrimaryButton(
                    label: 'დაწყება',
                    icon: Icons.arrow_forward,
                    // A venue with no name prints a blank line at the top of
                    // every check, so the name is the one thing required here.
                    onTap: named && !_saving ? _finish : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
