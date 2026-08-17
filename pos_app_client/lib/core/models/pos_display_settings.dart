import 'dart:ui';

import 'package:vynic/core/ui/vynic_breakpoints.dart';

enum PosLayoutClass {
  xs('xs'),
  sm('sm'),
  md('md'),
  lg('lg');

  const PosLayoutClass(this.label);

  final String label;

  bool get isXs => this == PosLayoutClass.xs;
  bool get isSm => this == PosLayoutClass.sm;
  bool get isCompactWidth =>
      this == PosLayoutClass.xs || this == PosLayoutClass.sm;

  /// Width the home-screen service rail should take at this size class.
  ///
  /// The rail stays docked on the right at every size that can actually
  /// spare the room — it only falls back to a bottom sheet when the
  /// remaining floor-plan area would be unusable. See
  /// [minWidthForInlineRail].
  double get sideRailWidth {
    switch (this) {
      case PosLayoutClass.xs:
        return 212;
      case PosLayoutClass.sm:
        return 244;
      case PosLayoutClass.md:
        return 272;
      case PosLayoutClass.lg:
        return 300;
    }
  }

  /// Content width below which the rail is worth more as a sheet than as a
  /// column: [sideRailWidth] plus a floor plan that is still legible.
  double get minWidthForInlineRail => sideRailWidth + 500;

  static PosLayoutClass forWidth(double width) {
    if (width < 1120) return PosLayoutClass.xs;
    if (width < 1330) return PosLayoutClass.sm;
    if (width < 1620) return PosLayoutClass.md;
    return PosLayoutClass.lg;
  }
}

enum PosDisplayMode {
  automatic('automatic'),
  fixed('fixed');

  const PosDisplayMode(this.storageValue);

  final String storageValue;

  static PosDisplayMode fromStorage(Object? value) {
    final normalized = value?.toString().toLowerCase().trim();
    return values.firstWhere(
      (mode) => mode.storageValue == normalized,
      orElse: () => PosDisplayMode.automatic,
    );
  }
}

enum PosUiDensity {
  compact('compact'),
  comfortable('comfortable');

  const PosUiDensity(this.storageValue);

  final String storageValue;

  static PosUiDensity fromStorage(Object? value) {
    final normalized = value?.toString().toLowerCase().trim();
    return values.firstWhere(
      (density) => density.storageValue == normalized,
      orElse: () => PosUiDensity.compact,
    );
  }
}

enum PosSidebarDefault {
  automatic('automatic'),
  expanded('expanded'),
  collapsed('collapsed');

  const PosSidebarDefault(this.storageValue);

  final String storageValue;

  static PosSidebarDefault fromStorage(Object? value) {
    final normalized = value?.toString().toLowerCase().trim();
    return values.firstWhere(
      (sidebar) => sidebar.storageValue == normalized,
      orElse: () => PosSidebarDefault.automatic,
    );
  }
}

enum PosTableTileSize {
  automatic('automatic'),
  small('small'),
  medium('medium'),
  large('large');

  const PosTableTileSize(this.storageValue);

  final String storageValue;

  static PosTableTileSize fromStorage(Object? value) {
    final normalized = value?.toString().toLowerCase().trim();
    return values.firstWhere(
      (size) => size.storageValue == normalized,
      orElse: () => PosTableTileSize.automatic,
    );
  }
}

class PosDisplaySettings {
  const PosDisplaySettings({
    this.displayMode = PosDisplayMode.automatic,
    this.density = PosUiDensity.compact,
    this.scalePercent = 100,
    this.sidebarDefault = PosSidebarDefault.automatic,
    this.tableTileSize = PosTableTileSize.automatic,
    this.fullscreenPosMode = false,
    this.floorPlanGrid = true,
  });

  final PosDisplayMode displayMode;
  final PosUiDensity density;
  final int scalePercent;
  final PosSidebarDefault sidebarDefault;
  final PosTableTileSize tableTileSize;
  final bool fullscreenPosMode;

  /// Draws the alignment grid behind the POS floor plan. Turning it off also
  /// drops the plan's own background fill, so the plan sits directly on the
  /// panel behind it instead of on a second, slightly different surface.
  final bool floorPlanGrid;

  static const defaults = PosDisplaySettings();

  double get scaleFactor => scalePercent / 100;

  PosDisplaySettings copyWith({
    PosDisplayMode? displayMode,
    PosUiDensity? density,
    int? scalePercent,
    PosSidebarDefault? sidebarDefault,
    PosTableTileSize? tableTileSize,
    bool? fullscreenPosMode,
    bool? floorPlanGrid,
  }) {
    return PosDisplaySettings(
      displayMode: displayMode ?? this.displayMode,
      density: density ?? this.density,
      scalePercent: (scalePercent ?? this.scalePercent).clamp(90, 110),
      sidebarDefault: sidebarDefault ?? this.sidebarDefault,
      tableTileSize: tableTileSize ?? this.tableTileSize,
      fullscreenPosMode: fullscreenPosMode ?? this.fullscreenPosMode,
      floorPlanGrid: floorPlanGrid ?? this.floorPlanGrid,
    );
  }

  PosUiDensity effectiveDensityForWidth(double width) {
    if (displayMode == PosDisplayMode.fixed) {
      return density;
    }
    return layoutClassForWidth(width) == PosLayoutClass.lg
        ? PosUiDensity.comfortable
        : PosUiDensity.compact;
  }

  PosLayoutClass layoutClassForWidth(double width) =>
      PosLayoutClass.forWidth(width);

  VynicLayoutMode effectiveLayoutModeForWidth(double width) {
    if (displayMode == PosDisplayMode.fixed) {
      return density == PosUiDensity.comfortable
          ? VynicLayoutMode.regular
          : VynicLayoutMode.compact;
    }
    switch (layoutClassForWidth(width)) {
      case PosLayoutClass.xs:
      case PosLayoutClass.sm:
        return VynicLayoutMode.compact;
      case PosLayoutClass.md:
        return VynicLayoutMode.regular;
      case PosLayoutClass.lg:
        return VynicLayoutMode.expanded;
    }
  }

  String activeLayoutLabel(Size size) {
    final densityLabel =
        effectiveDensityForWidth(size.width) == PosUiDensity.comfortable
        ? 'Comfortable'
        : 'Compact';
    if (displayMode == PosDisplayMode.fixed) {
      return 'Fixed · $densityLabel';
    }
    switch (layoutClassForWidth(size.width)) {
      case PosLayoutClass.xs:
        return '1024-1119 · $densityLabel';
      case PosLayoutClass.sm:
        return '1120-1329 · $densityLabel';
      case PosLayoutClass.md:
        return '1330-1619 · $densityLabel';
      case PosLayoutClass.lg:
        return '1620+ · $densityLabel';
    }
  }
}
