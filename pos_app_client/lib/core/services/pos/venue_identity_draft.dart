import 'dart:typed_data';

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
  VenueIdentityDraft() {
    _load();
  }

  late String _name;
  late String _address;
  late String _phone;
  late Uint8List? _logo;
  late ReceiptHeaderLayout _layout;

  String _savedName = '';
  String _savedAddress = '';
  String _savedPhone = '';
  Uint8List? _savedLogo;
  ReceiptHeaderLayout _savedLayout = const ReceiptHeaderLayout();

  /// The file the operator picked, kept so the ink threshold can re-trace
  /// without asking for it again. Null once saved and reopened — what is
  /// stored is already traced.
  Uint8List? sourceImage;

  void _load() {
    _savedName = DatabaseService.getVenueName();
    _savedAddress = DatabaseService.getVenueAddress();
    _savedPhone = DatabaseService.getVenuePhone();
    _savedLogo = DatabaseService.getVenueLogoPng();
    _savedLayout = DatabaseService.getReceiptHeaderLayout();

    _name = _savedName;
    _address = _savedAddress;
    _phone = _savedPhone;
    _logo = _savedLogo;
    _layout = _savedLayout;
  }

  String get name => _name;
  String get address => _address;
  String get phone => _phone;
  Uint8List? get logo => _logo;
  ReceiptHeaderLayout get layout => _layout;

  bool get hasName => _name.trim().isNotEmpty;

  bool get isDirty {
    return _name != _savedName ||
        _address != _savedAddress ||
        _phone != _savedPhone ||
        _layout != _savedLayout ||
        !_sameBytes(_logo, _savedLogo);
  }

  set name(String value) => _set(() => _name = value.trim());
  set address(String value) => _set(() => _address = value.trim());
  set phone(String value) => _set(() => _phone = value.trim());
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
    final logoChanged = !_sameBytes(_logo, _savedLogo);

    await DatabaseService.setVenueName(_name);
    await DatabaseService.setVenueAddress(_address);
    await DatabaseService.setVenuePhone(_phone);
    await DatabaseService.saveReceiptHeaderLayout(_layout);
    if (logoChanged) {
      await DatabaseService.setVenueLogoPng(_logo);
      PrinterService.clearReceiptLogoCache();
    }

    _savedName = _name;
    _savedAddress = _address;
    _savedPhone = _phone;
    _savedLogo = _logo;
    _savedLayout = _layout;
    notifyListeners();
  }

  /// Back to what is on disk, including the picked file.
  void revert() {
    _set(() {
      _name = _savedName;
      _address = _savedAddress;
      _phone = _savedPhone;
      _logo = _savedLogo;
      _layout = _savedLayout;
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
