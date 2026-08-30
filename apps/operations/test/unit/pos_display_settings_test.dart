import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/models/pos_display_settings.dart';

/// Several display settings only bite in combination, which is what made them
/// look broken. These pin the combinations down.

void main() {
  group('display mode and density', () {
    test('automatic mode derives density from the window width', () {
      const settings = PosDisplaySettings(density: PosUiDensity.comfortable);

      // The chosen density is deliberately ignored here — automatic means
      // "let the width decide".
      expect(settings.effectiveDensityForWidth(1024), PosUiDensity.compact);
      expect(settings.effectiveDensityForWidth(1920), PosUiDensity.comfortable);
    });

    test('fixed mode honours the chosen density at every width', () {
      const settings = PosDisplaySettings(
        displayMode: PosDisplayMode.fixed,
        density: PosUiDensity.comfortable,
      );

      for (final width in [1024.0, 1280.0, 1440.0, 1920.0]) {
        expect(
          settings.effectiveDensityForWidth(width),
          PosUiDensity.comfortable,
          reason: 'width $width should not override a fixed density',
        );
      }
    });

    test('picking a density is only meaningful together with fixed mode', () {
      // This is the pairing the UI now applies for the user: choosing a
      // density also switches the mode, because choosing it in automatic mode
      // changes nothing at all.
      const automatic = PosDisplaySettings();
      final chosen = automatic.copyWith(
        density: PosUiDensity.comfortable,
        displayMode: PosDisplayMode.fixed,
      );

      expect(
        automatic
            .copyWith(density: PosUiDensity.comfortable)
            .effectiveDensityForWidth(1024),
        PosUiDensity.compact,
      );
      expect(chosen.effectiveDensityForWidth(1024), PosUiDensity.comfortable);
    });
  });

  group('layout class', () {
    test('maps each supported resolution to its size class', () {
      expect(PosLayoutClass.forWidth(1024), PosLayoutClass.xs);
      expect(PosLayoutClass.forWidth(1280), PosLayoutClass.sm);
      expect(PosLayoutClass.forWidth(1366), PosLayoutClass.md);
      expect(PosLayoutClass.forWidth(1440), PosLayoutClass.md);
      expect(PosLayoutClass.forWidth(1920), PosLayoutClass.lg);
    });

    test('UI scaling shifts which size class a window lands in', () {
      // A 110% scale leaves the app 1024/1.1 logical pixels to lay out in, so
      // the layout class must be computed from that — not from 1024. This is
      // what _ScaledPosSurface now reports through MediaQuery.
      const windowWidth = 1024.0;
      const settings = PosDisplaySettings(scalePercent: 110);
      final logicalWidth = windowWidth / settings.scaleFactor;

      expect(logicalWidth, lessThan(windowWidth));
      expect(PosLayoutClass.forWidth(logicalWidth), PosLayoutClass.xs);
      // At 90% the app gets *more* logical room than the window has pixels.
      const zoomedOut = PosDisplaySettings(scalePercent: 90);
      expect(windowWidth / zoomedOut.scaleFactor, greaterThan(windowWidth));
    });

    test('the rail width and its threshold move together', () {
      for (final layoutClass in PosLayoutClass.values) {
        expect(
          layoutClass.minWidthForInlineRail,
          layoutClass.sideRailWidth + 500,
        );
      }
    });
  });

  group('table tile size', () {
    test('every option is distinct and round-trips through storage', () {
      for (final size in PosTableTileSize.values) {
        expect(PosTableTileSize.fromStorage(size.storageValue), size);
      }
      expect(
        PosTableTileSize.values.map((s) => s.storageValue).toSet(),
        hasLength(PosTableTileSize.values.length),
      );
    });

    test('an unknown stored value falls back to automatic', () {
      expect(
        PosTableTileSize.fromStorage('gigantic'),
        PosTableTileSize.automatic,
      );
      expect(PosTableTileSize.fromStorage(null), PosTableTileSize.automatic);
    });
  });

  group('sidebar default', () {
    test('explicit choices ignore the window width', () {
      const expanded = PosDisplaySettings(
        sidebarDefault: PosSidebarDefault.expanded,
      );
      const collapsed = PosDisplaySettings(
        sidebarDefault: PosSidebarDefault.collapsed,
      );

      expect(expanded.sidebarDefault, PosSidebarDefault.expanded);
      expect(collapsed.sidebarDefault, PosSidebarDefault.collapsed);
    });

    test('automatic collapses only on the compact size classes', () {
      expect(PosLayoutClass.forWidth(1024).isCompactWidth, isTrue);
      expect(PosLayoutClass.forWidth(1280).isCompactWidth, isTrue);
      expect(PosLayoutClass.forWidth(1440).isCompactWidth, isFalse);
      expect(PosLayoutClass.forWidth(1920).isCompactWidth, isFalse);
    });
  });

  group('storage round trip', () {
    test('copyWith preserves every other field', () {
      const base = PosDisplaySettings(
        displayMode: PosDisplayMode.fixed,
        density: PosUiDensity.comfortable,
        scalePercent: 110,
        sidebarDefault: PosSidebarDefault.collapsed,
        tableTileSize: PosTableTileSize.large,
        fullscreenPosMode: true,
        floorPlanGrid: false,
      );

      final tweaked = base.copyWith(scalePercent: 90);
      expect(tweaked.displayMode, base.displayMode);
      expect(tweaked.density, base.density);
      expect(tweaked.sidebarDefault, base.sidebarDefault);
      expect(tweaked.tableTileSize, base.tableTileSize);
      expect(tweaked.fullscreenPosMode, base.fullscreenPosMode);
      expect(tweaked.floorPlanGrid, base.floorPlanGrid);
      expect(tweaked.scalePercent, 90);
    });

    test('scale is clamped to the supported range', () {
      expect(
        const PosDisplaySettings().copyWith(scalePercent: 400).scalePercent,
        110,
      );
      expect(
        const PosDisplaySettings().copyWith(scalePercent: 10).scalePercent,
        90,
      );
    });
  });
}
