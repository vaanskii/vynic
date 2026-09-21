import 'dart:typed_data';
import 'dart:async';
import '../../database/database_core.dart';
import '../edge/edge_device_credential_store.dart';
import '../edge/runtime_config_sync.dart';

import 'package:flutter/foundation.dart';

import 'package:vynic/core/models/receipt_header_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/printing/printer_service.dart';

/// The venue's header, being edited.
///
/// Every field used to write straight through to the database the moment it
/// changed: pick a logo and it was live, tap an alignment and the next check
/// printed differently. Fine for a toggle, wrong for a header — an operator
/// trying arrangements was changing what customers were handed, mid-shift,
/// with no way back.
///
/// So edits land here and go no further until [save]. [revert] puts everything
/// back to what is actually stored.
class VenueIdentityDraft extends ChangeNotifier {
  VenueIdentityDraft({bool watchProfile = false}) {
    _load();
    if (watchProfile) {
      _profileChanges = DatabaseCore.settingsBox?.watch().listen((event) {
        if (!_saving &&
            !isDirty &&
            const {
              'venueName',
              'venueBranchName',
              'venueAddress',
              'venuePhone',
              'venueLegalId',
            }.contains(event.key)) {
          _load();
          notifyListeners();
        }
      });
    }
  }
  StreamSubscription<dynamic>? _profileChanges;
  bool _saving = false;
  @override
  void dispose() {
    unawaited(_profileChanges?.cancel());
    super.dispose();
  }

  late String _name;
  String _branchName = '';
  String _savedBranchName = '';
  late String _address;
  late String _phone;
  late String _legalId;
  late Uint8List? _logo;
  late ReceiptHeaderLayout _layout;

  String _savedName = '';
  String _savedAddress = '';
  String _savedPhone = '';
  String _savedLegalId = '';
  Uint8List? _savedLogo;
  ReceiptHeaderLayout _savedLayout = const ReceiptHeaderLayout();

  /// The file the operator picked, kept so the ink threshold can re-trace
  /// without asking for it again. Null once saved and reopened — what is
  /// stored is already traced.
  Uint8List? sourceImage;

  void _load() {
    _savedBranchName =
        DatabaseCore.settingsBox?.get('venueBranchName') as String? ?? '';
    _branchName = _savedBranchName;
    _savedName = DatabaseService.getVenueName();
    _savedAddress = DatabaseService.getVenueAddress();
    _savedPhone = DatabaseService.getVenuePhone();
    _savedLegalId = DatabaseService.getVenueLegalId();
    _savedLogo = DatabaseService.getVenueLogoPng();
    _savedLayout = DatabaseService.getReceiptHeaderLayout();

    _name = _savedName;
    _address = _savedAddress;
    _phone = _savedPhone;
    _legalId = _savedLegalId;
    _logo = _savedLogo;
    _layout = _savedLayout;
  }

  String get name => _name;
  String get branchName => _branchName;
  set branchName(String value) => _set(() => _branchName = value.trim());
  String get address => _address;
  String get phone => _phone;

  /// The venue's legal/registration identifier, printed on financial reports.
  /// Empty is a valid state — the report says the field is unconfigured
  /// rather than borrowing another venue's number.
  String get legalId => _legalId;
  Uint8List? get logo => _logo;
  ReceiptHeaderLayout get layout => _layout;

  bool get hasName => _name.trim().isNotEmpty;

  bool get isDirty {
    return _branchName != _savedBranchName ||
        _name != _savedName ||
        _address != _savedAddress ||
        _phone != _savedPhone ||
        _legalId != _savedLegalId ||
        _layout != _savedLayout ||
        !_sameBytes(_logo, _savedLogo);
  }

  set name(String value) => _set(() => _name = value.trim());
  set address(String value) => _set(() => _address = value.trim());
  set phone(String value) => _set(() => _phone = value.trim());
  set legalId(String value) => _set(() => _legalId = value.trim());
  set layout(ReceiptHeaderLayout value) => _set(() => _layout = value);

  void setLogo(Uint8List? png, {Uint8List? source}) {
    _set(() {
      _logo = png;
      if (source != null) sourceImage = source;
      if (png == null) sourceImage = null;
    });
  }

  void _set(VoidCallback mutate) {
    mutate();
    notifyListeners();
  }

  /// Writes everything at once.
  ///
  /// The logo cache is dropped only when the logo actually changed — clearing
  /// it forces the next receipt to decode the image again, which is wasted
  /// work if all that moved was an alignment.
  Future<void> save() async {
    _saving = true;
    try {
      final profileChanged =
          _name != _savedName ||
          _branchName != _savedBranchName ||
          _address != _savedAddress ||
          _phone != _savedPhone ||
          _legalId != _savedLegalId;
      if (profileChanged && EdgeDeviceCredentialStore.hasCredential) {
        if (!hasName) throw StateError('შეიყვანეთ რესტორნის სახელი');
        if (_name.length > 100 ||
            _branchName.length > 100 ||
            _address.length > 300 ||
            _phone.length > 50 ||
            _legalId.length > 50)
          throw StateError('პროფილის ველი ზედმეტად გრძელია');
        await DatabaseCore.settingsBox!.put('pendingVenueProfile', {
          'venueId': EdgeDeviceCredentialStore.venueId,
          'profile': {
            'name': _name,
            'branchName': _branchName,
            'address': _address,
            'phone': _phone,
            'legalId': _legalId,
          },
        });
      }
      await DatabaseCore.settingsBox?.put('venueBranchName', _branchName);
      final logoChanged = !_sameBytes(_logo, _savedLogo);

      await DatabaseService.setVenueName(_name);
      await DatabaseService.setVenueAddress(_address);
      await DatabaseService.setVenuePhone(_phone);
      await DatabaseService.setVenueLegalId(_legalId);
      await DatabaseService.saveReceiptHeaderLayout(_layout);
      if (logoChanged) {
        await DatabaseService.setVenueLogoPng(_logo);
        PrinterService.clearReceiptLogoCache();
      }

      _savedBranchName = _branchName;
      _savedName = _name;
      _savedAddress = _address;
      _savedPhone = _phone;
      _savedLegalId = _legalId;
      _savedLogo = _logo;
      _savedLayout = _layout;
      if (profileChanged && EdgeDeviceCredentialStore.hasCredential)
        unawaited(RuntimeConfigSync.instance.pull());
      notifyListeners();
    } finally {
      _saving = false;
    }
  }

  /// Back to what is on disk, including the picked file.
  void revert() {
    _set(() {
      _load();
      sourceImage = null;
    });
  }

  static bool _sameBytes(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
