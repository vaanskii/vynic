import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/venue_identity_draft.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/shared/venue_identity_panel.dart';

/// The one screen a terminal shows before it has ever been used.
///
/// A POS out of the box used to come up as this restaurant: nine tables, four
/// VIP booths, a full Georgian menu and a manager called „vaanskii". A venue
/// had to delete all of it before it could enter its own. Now it comes up
/// empty and asks a single question.
///
/// Only the name is asked here. Printers, the backend address and the floor
/// plan are all things that need a network, a printer on a desk, and a room to
/// look at — they belong in Settings, where they can be changed again when the
/// second printer arrives.
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

  @override
  void initState() {
    super.initState();
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
    setState(() => _saving = true);
    await _draft.save();
    await DatabaseService.markSetupComplete();
    if (!mounted) return;
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
                    'სახელი და ლოგო ჩეკის თავში დაიბეჭდება. '
                    'მაგიდები, მენიუ და პრინტერები ცარიელია — '
                    'მათ პარამეტრებიდან დაამატებთ.',
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
                    showAddressAndPhone: false,
                    showSaveButton: false,
                  ),
                  const SizedBox(height: 20),
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
