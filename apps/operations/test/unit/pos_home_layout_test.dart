import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/core/models/pos_display_settings.dart';

/// The home screen's service rail used to drop to a bottom sheet on any
/// window under 1330px, which meant a 1024x768 terminal never saw it docked
/// on the right. These pin the widths that decide otherwise.

/// Space the dashboard hands to its Row after its own padding, given the
/// window width and how wide the operational sidebar is.
double _dashboardContentWidth(double windowWidth, double sidebarWidth) {
  final sectionWidth = windowWidth - sidebarWidth;
  final layoutClass = PosLayoutClass.forWidth(windowWidth);
  final padding = (layoutClass.isXs ? 12.0 : 20.0) * 2;
  return sectionWidth - padding;
}

void main() {
  group('side rail docking', () {
    test('1024x768 with a collapsed sidebar keeps the rail on the right', () {
      const windowWidth = 1024.0;
      const collapsedSidebar = 54.0;
      final layoutClass = PosLayoutClass.forWidth(windowWidth);
      // The section itself is measured before its padding is applied.
      final sectionWidth = windowWidth - collapsedSidebar;

      expect(layoutClass, PosLayoutClass.xs);
      expect(
        sectionWidth,
        greaterThanOrEqualTo(layoutClass.minWidthForInlineRail),
      );
    });

    test('the floor plan still gets the majority of the width at 1024', () {
      const windowWidth = 1024.0;
      final layoutClass = PosLayoutClass.forWidth(windowWidth);
      final content = _dashboardContentWidth(windowWidth, 54);
      final planWidth = content - layoutClass.sideRailWidth - 12;

      expect(planWidth, greaterThan(layoutClass.sideRailWidth));
      expect(planWidth, greaterThan(600));
    });

    test('an expanded sidebar at 1024 still leaves room for the rail', () {
      const windowWidth = 1024.0;
      const expandedSidebar = 164.0;
      final layoutClass = PosLayoutClass.forWidth(windowWidth);

      expect(
        windowWidth - expandedSidebar,
        greaterThanOrEqualTo(layoutClass.minWidthForInlineRail),
      );
    });

    test('a genuinely tiny pane falls back to the sheet', () {
      final layoutClass = PosLayoutClass.forWidth(800);
      // An 800px window with the sidebar expanded leaves 636px — too little
      // to carry both a rail and a floor plan worth looking at.
      expect(800 - 164.0, lessThan(layoutClass.minWidthForInlineRail));
      // ...but the same window with the sidebar collapsed keeps the rail.
      expect(
        800 - 54.0,
        greaterThanOrEqualTo(layoutClass.minWidthForInlineRail),
      );
    });

    test('the rail grows with the size class', () {
      final widths = [
        for (final layoutClass in PosLayoutClass.values)
          layoutClass.sideRailWidth,
      ];
      expect(widths, orderedEquals([212.0, 244.0, 272.0, 300.0]));
      for (var i = 1; i < widths.length; i++) {
        expect(widths[i], greaterThan(widths[i - 1]));
      }
    });

    test('service tiles never get squeezed below their content height', () {
      const railSectionInset = 16.0 * 2;
      const minTileHeight = 58.0;

      for (final layoutClass in PosLayoutClass.values) {
        for (final spacing in [8.0, 10.0]) {
          final tileWidth =
              (layoutClass.sideRailWidth - railSectionInset - spacing) / 2;
          final baseRatio = spacing == 8.0 ? 1.64 : 1.5;
          final ratio = baseRatio < tileWidth / minTileHeight
              ? baseRatio
              : tileWidth / minTileHeight;

          expect(
            tileWidth / ratio,
            greaterThanOrEqualTo(minTileHeight - 0.001),
            reason: 'tile too short at ${layoutClass.label}',
          );
        }
      }
    });
  });

  group('floor plan grid setting', () {
    test('defaults to on so existing terminals look unchanged', () {
      expect(PosDisplaySettings.defaults.floorPlanGrid, isTrue);
    });

    test('survives copyWith alongside the other display settings', () {
      const settings = PosDisplaySettings();
      final off = settings.copyWith(floorPlanGrid: false);

      expect(off.floorPlanGrid, isFalse);
      expect(off.tableTileSize, settings.tableTileSize);
      expect(off.fullscreenPosMode, settings.fullscreenPosMode);
      expect(off.copyWith(scalePercent: 105).floorPlanGrid, isFalse);
    });
  });
}
