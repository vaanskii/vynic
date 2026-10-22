/// Command language is independent of TCP or Windows RAW spooler delivery.
/// Driver-rendered output is reserved for a future renderer, not implemented.
enum PrinterCommandLanguage { escposRaster, windowsDriverRendered }

enum PrinterCutter { none, full, partial }

/// Georgian text is rendered into pixels, never an assumed printer code page.
enum PrinterTextEncoding { georgianViaRaster }

enum PrinterBeepCapability {
  unknown,
  unsupported,

  /// Explicit compatibility with Epson ESC ( A fn=97's registered-pattern
  /// variant (pL=3), including a configured compatible buzzer. General ESC/POS
  /// support alone does not establish this optional capability.
  epsonEscA97Pattern,
}

class PrinterBeepSettings {
  const PrinterBeepSettings({
    this.capability = PrinterBeepCapability.unknown,
    this.enabled = false,
  });

  final PrinterBeepCapability capability;
  final bool enabled;

  /// Unrecognized optional configuration disables sound without rejecting the
  /// primary printing profile. Arbitrary command bytes are never accepted.
  factory PrinterBeepSettings.decode(dynamic raw) {
    if (raw is! Map ||
        raw.length != 2 ||
        raw['enabled'] is! bool ||
        !PrinterBeepCapability.values.any(
          (value) => value.name == raw['capability'],
        )) {
      return const PrinterBeepSettings();
    }
    return PrinterBeepSettings(
      capability: PrinterBeepCapability.values.byName(raw['capability']),
      enabled: raw['enabled'],
    );
  }

  Map<String, dynamic> toMap() => {
    'capability': capability.name,
    'enabled': enabled,
  };
}

/// Manually configured capabilities, never inferred from a vendor name,
/// driver, port, network probe, or model identifier. ESC/POS-compatible vendors
/// share the raster path; each installation supplies its actual dimensions and
/// cutter capability. A profile is configuration, not hardware qualification.
class PrinterCapabilityProfile {
  PrinterCapabilityProfile._({
    required this.paperWidthMm,
    required this.rasterWidthDots,
    required this.language,
    required this.cutter,
    required this.encoding,
    required this.beep,
  });

  final int paperWidthMm;
  final int rasterWidthDots;
  final PrinterCommandLanguage language;
  final PrinterCutter cutter;
  final PrinterTextEncoding encoding;
  final PrinterBeepSettings beep;

  bool get hasImplementedRenderer =>
      language == PrinterCommandLanguage.escposRaster;

  factory PrinterCapabilityProfile({
    required int paperWidthMm,
    required int rasterWidthDots,
    required PrinterCommandLanguage language,
    required PrinterCutter cutter,
    PrinterTextEncoding encoding = PrinterTextEncoding.georgianViaRaster,
    PrinterBeepSettings beep = const PrinterBeepSettings(),
  }) => PrinterCapabilityProfile.decode({
    'protocol': 1,
    'paperWidthMm': paperWidthMm,
    'rasterWidthDots': rasterWidthDots,
    'language': language.name,
    'cutter': cutter.name,
    'encoding': encoding.name,
    'beep': beep.toMap(),
  });

  factory PrinterCapabilityProfile.genericEscposRaster({
    int paperWidthMm = 80,
    int rasterWidthDots = 576,
    PrinterCutter cutter = PrinterCutter.none,
    PrinterBeepSettings beep = const PrinterBeepSettings(),
  }) => PrinterCapabilityProfile(
    paperWidthMm: paperWidthMm,
    rasterWidthDots: rasterWidthDots,
    language: PrinterCommandLanguage.escposRaster,
    cutter: cutter,
    beep: beep,
  );

  factory PrinterCapabilityProfile.decode(dynamic raw) {
    const fields = {
      'protocol',
      'paperWidthMm',
      'rasterWidthDots',
      'language',
      'cutter',
      'encoding',
      'beep',
    };
    if (raw is! Map ||
        raw.keys.toSet().difference(fields).isNotEmpty ||
        raw['protocol'] is! int ||
        raw['protocol'] != 1 ||
        raw['paperWidthMm'] is! int ||
        raw['paperWidthMm'] < 40 ||
        raw['paperWidthMm'] > 120 ||
        raw['rasterWidthDots'] is! int ||
        raw['rasterWidthDots'] < 64 ||
        raw['rasterWidthDots'] > 2048 ||
        raw['rasterWidthDots'] % 8 != 0 ||
        !PrinterCommandLanguage.values.any(
          (value) => value.name == raw['language'],
        ) ||
        !PrinterCutter.values.any((value) => value.name == raw['cutter']) ||
        !PrinterTextEncoding.values.any(
          (value) => value.name == raw['encoding'],
        )) {
      throw const FormatException('Invalid printer capability profile');
    }
    return PrinterCapabilityProfile._(
      paperWidthMm: raw['paperWidthMm'],
      rasterWidthDots: raw['rasterWidthDots'],
      language: PrinterCommandLanguage.values.byName(raw['language']),
      cutter: PrinterCutter.values.byName(raw['cutter']),
      encoding: PrinterTextEncoding.values.byName(raw['encoding']),
      beep: PrinterBeepSettings.decode(raw['beep']),
    );
  }

  Map<String, dynamic> toMap() => {
    'protocol': 1,
    'paperWidthMm': paperWidthMm,
    'rasterWidthDots': rasterWidthDots,
    'language': language.name,
    'cutter': cutter.name,
    'encoding': encoding.name,
    'beep': beep.toMap(),
  };
}
