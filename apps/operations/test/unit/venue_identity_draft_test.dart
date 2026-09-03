import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/settings_repository.dart';
import 'package:vynic/core/models/receipt_header_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/services/pos/venue_identity_draft.dart';

/// Editing the venue header without changing what customers are handed.
///
/// Every field used to write straight through: pick a logo and it was live,
/// tap an alignment and the next check printed differently. An operator trying
/// arrangements was doing it on real receipts, mid-shift, with no way back.

late Directory _tempDir;

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  setUpAll(() async {
    _tempDir = await Directory.systemTemp.createTemp('vynic_venue_draft');
    Hive.init(_tempDir.path);
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('vd_settings');
    DatabaseCore.settingsBox = await Hive.openBox('vd_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    DatabaseCore.settingsBox = null;
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  group('a draft holds edits back', () {
    test('starts clean, and typing makes it dirty', () {
      final draft = VenueIdentityDraft();
      expect(draft.isDirty, isFalse);

      draft.name = 'ღვინის სახლი';
      expect(draft.isDirty, isTrue);
      // ...and the database has not been touched.
      expect(DatabaseService.getVenueName(), '');
    });

    test('nothing reaches the database until save', () async {
      final draft = VenueIdentityDraft()
        ..name = 'ღვინის სახლი'
        ..address = 'რუსთაველის 12'
        ..phone = '+995 555 00 11 22'
        ..layout = const ReceiptHeaderLayout(logoAlign: ReceiptAlign.left);

      expect(DatabaseService.getVenueName(), '');
      expect(DatabaseService.getVenueAddress(), '');

      await draft.save();

      expect(DatabaseService.getVenueName(), 'ღვინის სახლი');
      expect(DatabaseService.getVenueAddress(), 'რუსთაველის 12');
      expect(DatabaseService.getVenuePhone(), '+995 555 00 11 22');
      expect(
        DatabaseService.getReceiptHeaderLayout().logoAlign,
        ReceiptAlign.left,
      );
      expect(draft.isDirty, isFalse);
    });

    test('revert puts back what is on disk', () async {
      await SettingsRepository.setVenueName('ძველი სახელი');
      final draft = VenueIdentityDraft()..name = 'ახალი სახელი';

      draft.revert();

      expect(draft.name, 'ძველი სახელი');
      expect(draft.isDirty, isFalse);
      expect(DatabaseService.getVenueName(), 'ძველი სახელი');
    });

    test('a name of spaces does not count as a name', () {
      // „Start" on the setup screen is gated on this, and a venue called
      // „   " prints a blank line at the top of every check.
      final draft = VenueIdentityDraft()..name = '   ';
      expect(draft.hasName, isFalse);
    });

    test('setting a field back to its saved value is not dirty', () {
      final draft = VenueIdentityDraft()..name = 'x';
      expect(draft.isDirty, isTrue);
      draft.name = '';
      expect(draft.isDirty, isFalse);
    });
  });

  group('the logo', () {
    test('is compared by content, not identity', () {
      // Two lists with the same bytes are the same logo. Comparing references
      // would leave the save button lit after every re-trace.
      final draft = VenueIdentityDraft()..setLogo(_bytes([1, 2, 3]));
      expect(draft.isDirty, isTrue);

      draft.setLogo(null);
      expect(draft.isDirty, isFalse);
    });

    test('removing a saved logo is a change worth saving', () async {
      await SettingsRepository.setVenueLogoPng(_bytes([9, 9, 9]));
      final draft = VenueIdentityDraft();
      expect(draft.isDirty, isFalse);

      draft.setLogo(null);
      expect(draft.isDirty, isTrue);

      await draft.save();
      expect(DatabaseService.getVenueLogoPng(), isNull);
    });

    test('clearing the logo forgets the file it was traced from', () {
      // The threshold slider only exists while there is a source to re-trace.
      final draft = VenueIdentityDraft()
        ..setLogo(_bytes([1, 2]), source: _bytes([3, 4]));
      expect(draft.sourceImage, isNotNull);

      draft.setLogo(null);
      expect(draft.sourceImage, isNull);
    });
  });

  group('surviving a backup', () {
    test('a logo written out as a JSON list is read back as bytes', () async {
      // This is how it comes back off a restore: the settings box is
      // serialised to JSON, so the bytes return as `List<dynamic>`, not
      // `List<int>`. A type check for the latter alone dropped the venue's
      // logo silently on every restore.
      await DatabaseCore.settingsBox!.put('venueLogoPng', <dynamic>[
        137,
        80,
        78,
        71,
        13,
        10,
      ]);

      final restored = DatabaseService.getVenueLogoPng();
      expect(restored, isNotNull);
      expect(restored, _bytes([137, 80, 78, 71, 13, 10]));
    });

    test('a list of something else is refused rather than corrupted', () async {
      await DatabaseCore.settingsBox!.put('venueLogoPng', <dynamic>['a', 'b']);
      expect(DatabaseService.getVenueLogoPng(), isNull);
    });

    test('an empty stored logo reads as no logo', () async {
      await DatabaseCore.settingsBox!.put('venueLogoPng', <dynamic>[]);
      expect(DatabaseService.getVenueLogoPng(), isNull);
    });
  });

  group('logo size', () {
    test('round-trips through the settings box', () async {
      final draft = VenueIdentityDraft()
        ..layout = const ReceiptHeaderLayout(logoScale: 0.5);
      await draft.save();

      expect(DatabaseService.getReceiptHeaderLayout().logoScale, 0.5);
    });

    test('is clamped on the way out, so a bad value cannot overrun', () async {
      final draft = VenueIdentityDraft()
        ..layout = const ReceiptHeaderLayout(logoScale: 9);
      await draft.save();

      expect(
        DatabaseService.getReceiptHeaderLayout().clampedScale,
        ReceiptHeaderLayout.maxScale,
      );
    });

    test('a terminal that predates the setting prints at full size', () {
      // Which is exactly what it printed before the size was settable.
      expect(DatabaseService.getReceiptHeaderLayout().logoScale, 1.0);
    });
  });
}
