import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/services/edge/edge_device_credential_store.dart';
import 'package:vynic/core/services/edge/pos_enrollment_service.dart';
import 'package:vynic/core/services/sync/api_config.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// Connect this POS to Vynic.
///
/// One screen for what used to be two unrelated manual steps done in the right
/// order: a credential file written next to the data directory by hand, and a
/// backend address typed into a different panel. An operator now types the
/// address once and a code once, and the terminal says which restaurant it
/// ended up in — which is the confirmation neither side used to get.
///
/// An enrolled terminal keeps this panel as a read-only statement of what it
/// is, because "which venue does this till belong to" is a question worth being
/// able to answer without a support call.
class AdminPosEnrollmentPanel extends StatefulWidget {
  const AdminPosEnrollmentPanel({super.key, this.service});

  /// Test seam.
  final PosEnrollmentService? service;

  @override
  State<AdminPosEnrollmentPanel> createState() =>
      _AdminPosEnrollmentPanelState();
}

class _AdminPosEnrollmentPanelState extends State<AdminPosEnrollmentPanel> {
  late final PosEnrollmentService _service =
      widget.service ?? PosEnrollmentService();
  late final TextEditingController _addressController = TextEditingController(
    text: ApiConfig.baseUrl,
  );
  final TextEditingController _codeController = TextEditingController();

  bool _connecting = false;
  bool _expanded = false;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void dispose() {
    _addressController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool get _enrolled => EdgeDeviceCredentialStore.hasCredential;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _enrolled ? Icons.verified_outlined : Icons.link_off,
                color: _enrolled ? AdminDesign.accentDark : AdminDesign.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Vynic Cloud',
                  style: TextStyle(
                    color: AdminDesign.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AdminStatusBadge(
                icon: _enrolled ? Icons.check_circle : Icons.schedule,
                label: _enrolled ? 'Enrolled' : 'Not connected',
                color: _enrolled ? AdminDesign.accentDark : AdminDesign.warning,
                background: _enrolled
                    ? AdminTones.successFill
                    : AdminTones.warningFill,
                border: _enrolled
                    ? AdminTones.successBorder
                    : AdminTones.warningBorder,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_enrolled) ..._enrolledRows() else ..._invitation(),
          if (_expanded || !_enrolled) ...[const SizedBox(height: 12), _form()],
          if (_feedback != null) ...[
            const SizedBox(height: 12),
            _Feedback(message: _feedback!, isError: _feedbackIsError),
          ],
        ],
      ),
    );
  }

  List<Widget> _enrolledRows() {
    final venue = EdgeDeviceCredentialStore.venueName;
    return <Widget>[
      _Row(
        label: 'Venue',
        value: venue == null || venue.isEmpty ? 'Not reported' : venue,
      ),
      _Row(
        label: 'Device ID',
        value: EdgeDeviceCredentialStore.deviceId ?? 'Unknown',
      ),
      _Row(
        label: 'Installation ID',
        value: EdgeDeviceCredentialStore.installationId ?? 'Unknown',
      ),
      _Row(label: 'Backend URL', value: ApiConfig.baseUrl),
      const SizedBox(height: 4),
      const Text(
        'Enrolling again rotates this terminal’s credential. It stays the '
        'same device, and the old credential stops working immediately.',
        style: TextStyle(color: AdminDesign.muted, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: AdminDesign.outlineButtonStyle(),
        onPressed: _connecting
            ? null
            : () => setState(() => _expanded = !_expanded),
        icon: Icon(_expanded ? Icons.close : Icons.autorenew, size: 18),
        label: Text(_expanded ? 'Cancel' : 'Re-enrol this POS'),
      ),
    ];
  }

  List<Widget> _invitation() => <Widget>[
    const Text(
      'This terminal has no Vynic identity yet, so it works locally but does '
      'not sync. Ask a Vynic administrator for an enrollment code for your '
      'venue, then enter this server’s address and the code below.',
      style: TextStyle(color: AdminDesign.muted, fontSize: 13, height: 1.45),
    ),
  ];

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _addressController,
          enabled: !_connecting,
          decoration: InputDecoration(
            labelText: 'Server address',
            hintText: 'http://10.10.10.3:3000',
            helperText: '10.10.10.3 becomes http://10.10.10.3:3000',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AdminDesign.radius),
            ),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeController,
          enabled: !_connecting,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(20),
            UpperCaseFormatter(),
          ],
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
          decoration: InputDecoration(
            labelText: 'Enrollment code',
            hintText: '7K2Q-M4XB-9TFR',
            helperText: 'Twelve characters. Dashes and spaces do not matter.',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AdminDesign.radius),
            ),
            isDense: true,
          ),
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: AdminDesign.primaryButtonStyle(),
          onPressed: _connecting ? null : _connect,
          icon: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.link, size: 18),
          label: Text(
            _enrolled ? 'Re-enrol this POS' : 'Connect this POS to Vynic',
          ),
        ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _feedback = 'Contacting the server…';
      _feedbackIsError = false;
    });

    final result = await _service.enroll(
      serverAddress: _addressController.text,
      code: _codeController.text,
    );
    if (!mounted) return;

    setState(() {
      _connecting = false;
      _feedbackIsError = !result.isConnected;
      if (result.isConnected) {
        _codeController.clear();
        _expanded = false;
        final venue = result.venueName;
        _feedback = venue == null || venue.isEmpty
            ? 'Connected. This POS is enrolled with Vynic.'
            : 'Connected. This POS is enrolled with $venue.';
      } else {
        _feedback = result.message ?? 'Enrollment failed.';
      }
    });
  }
}

/// Codes are printed uppercase, so the field shows them that way while typing.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: AdminDesign.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: AdminDesign.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AdminDesign.danger : AdminDesign.accentDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? VynicFloorTokens.dangerFill : AdminTones.successFill,
        borderRadius: BorderRadius.circular(AdminDesign.radius),
        border: Border.all(
          color: isError
              ? VynicFloorTokens.dangerBorder
              : AdminTones.successBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
