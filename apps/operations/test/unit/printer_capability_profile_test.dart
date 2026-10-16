import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/services/printing/printer_capability_profile.dart';

void main() {
  test('generic raster profile has no vendor or transport assumptions', () {
    final profile = PrinterCapabilityProfile.genericEscposRaster();
    expect(profile.paperWidthMm, 80);
    expect(profile.rasterWidthDots, 576);
    expect(profile.language, PrinterCommandLanguage.escposRaster);
    expect(profile.encoding, PrinterTextEncoding.georgianViaRaster);
    expect(profile.hasImplementedRenderer, true);
    expect(profile.cutter, PrinterCutter.none);
    expect(profile.beep.enabled, false);
    expect(profile.beep.capability, PrinterBeepCapability.unknown);
    expect(
      profile.toMap().keys,
      unorderedEquals([
        'protocol',
        'paperWidthMm',
        'rasterWidthDots',
        'language',
        'cutter',
        'encoding',
        'beep',
      ]),
    );
  });

  test('manually supplied widths and cutters survive profile round trip', () {
    for (final dimensions in [(58, 384), (80, 512), (80, 576), (112, 832)]) {
      for (final cutter in PrinterCutter.values) {
        final profile = PrinterCapabilityProfile.genericEscposRaster(
          paperWidthMm: dimensions.$1,
          rasterWidthDots: dimensions.$2,
          cutter: cutter,
        );
        final decoded = PrinterCapabilityProfile.decode(profile.toMap());
        expect(decoded.paperWidthMm, dimensions.$1);
        expect(decoded.rasterWidthDots, dimensions.$2);
        expect(decoded.cutter, cutter);
        expect(decoded.encoding, PrinterTextEncoding.georgianViaRaster);
        expect(decoded.toMap(), profile.toMap());
      }
    }
  });

  test('driver-rendered language is representable but not implemented', () {
    final profile = PrinterCapabilityProfile(
      paperWidthMm: 80,
      rasterWidthDots: 576,
      language: PrinterCommandLanguage.windowsDriverRendered,
      cutter: PrinterCutter.partial,
    );
    final decoded = PrinterCapabilityProfile.decode(profile.toMap());
    expect(decoded.language, PrinterCommandLanguage.windowsDriverRendered);
    expect(decoded.hasImplementedRenderer, false);
  });

  test(
    'primary capability errors reject before any rendering or transport',
    () {
      final valid = PrinterCapabilityProfile.genericEscposRaster().toMap();
      for (final change in [
        {'protocol': 1.0},
        {'protocol': 2},
        {'paperWidthMm': 39},
        {'paperWidthMm': 121},
        {'paperWidthMm': '80'},
        {'rasterWidthDots': 63},
        {'rasterWidthDots': 65},
        {'rasterWidthDots': 2056},
        {'rasterWidthDots': 576.0},
        {'language': 'arbitraryRaw'},
        {'cutter': 'drawerPulse'},
        {'encoding': 'assumeGeorgianCodePage'},
        {'transport': 'tcp'},
        {
          'command': [0x07],
        },
      ]) {
        expect(
          () => PrinterCapabilityProfile.decode({...valid, ...change}),
          throwsFormatException,
          reason: change.toString(),
        );
      }
      for (final raw in [null, true, [], {}, 'escposRaster']) {
        expect(
          () => PrinterCapabilityProfile.decode(raw),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'unknown or malformed optional beep does not reject primary profile',
    () {
      final valid = PrinterCapabilityProfile.genericEscposRaster().toMap();
      final missing = {...valid}..remove('beep');
      final unknown = [
        null,
        true,
        'BEL',
        [],
        {},
        {'capability': 'starVendorSpecific', 'enabled': true},
        {'capability': 'epsonEscA97Pattern', 'enabled': 'true'},
        {'capability': 'epsonEscA97Pattern'},
        {
          'capability': 'epsonEscA97Pattern',
          'enabled': true,
          'command': [0x07],
        },
      ];
      for (final raw in [
        missing,
        for (final beep in unknown) {...valid, 'beep': beep},
      ]) {
        final profile = PrinterCapabilityProfile.decode(raw);
        expect(profile.paperWidthMm, 80);
        expect(profile.rasterWidthDots, 576);
        expect(profile.hasImplementedRenderer, true);
        expect(profile.beep.capability, PrinterBeepCapability.unknown);
        expect(profile.beep.enabled, false);
      }
    },
  );

  test('explicit beep capability and enablement remain separate', () {
    for (final capability in PrinterBeepCapability.values) {
      for (final enabled in [false, true]) {
        final profile = PrinterCapabilityProfile.genericEscposRaster(
          beep: PrinterBeepSettings(capability: capability, enabled: enabled),
        );
        final decoded = PrinterCapabilityProfile.decode(profile.toMap());
        expect(decoded.beep.capability, capability);
        expect(decoded.beep.enabled, enabled);
      }
    }
  });

  test('profile snapshots detach from both input and exported maps', () {
    final input = PrinterCapabilityProfile.genericEscposRaster(
      cutter: PrinterCutter.full,
      beep: const PrinterBeepSettings(
        capability: PrinterBeepCapability.epsonEscA97Pattern,
        enabled: true,
      ),
    ).toMap();
    final profile = PrinterCapabilityProfile.decode(input);
    input['rasterWidthDots'] = 384;
    (input['beep'] as Map)['enabled'] = false;
    final output = profile.toMap();
    output['paperWidthMm'] = 58;
    (output['beep'] as Map)['capability'] = 'unsupported';
    expect(profile.paperWidthMm, 80);
    expect(profile.rasterWidthDots, 576);
    expect(profile.cutter, PrinterCutter.full);
    expect(profile.beep.enabled, true);
    expect(profile.beep.capability, PrinterBeepCapability.epsonEscA97Pattern);
  });
}
