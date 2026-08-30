// Tests for the UI Phase 2 token layer (docs/UI_TOKENS.md / UI_RESPONSIVE.md).
// These lock the invariants future phases depend on: every operational state
// resolves to a token, touch-target floors stay >= 44/36, motion stays within
// the allowed set, and the responsive width rules never overflow a 1280×720
// terminal.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/ui/vynic_breakpoints.dart';
import 'package:vynic/core/ui/vynic_motion.dart';
import 'package:vynic/core/ui/vynic_responsive.dart';
import 'package:vynic/core/ui/vynic_status_tokens.dart';
import 'package:vynic/core/ui/vynic_text_styles.dart';
import 'package:vynic/core/ui/vynic_touch_targets.dart';

void main() {
  group('Status tokens', () {
    test('every operational state resolves to a token', () {
      for (final state in VynicOperationalState.values) {
        final token = VynicStatusTokens.ofState(state);
        expect(
          token.tone,
          VynicStatusTokens.toneForState(state),
          reason: '$state token/tone mismatch',
        );
      }
    });

    test('every tone resolves to a distinct three-color token', () {
      for (final tone in VynicStatusTone.values) {
        final token = VynicStatusTokens.ofTone(tone);
        expect(token.tone, tone);
        // foreground must differ from its own soft background (contrast).
        expect(token.foreground, isNot(token.background));
      }
    });

    test('all 16 §3 states are represented', () {
      expect(VynicOperationalState.values.length, 16);
    });

    test('chip text meets WCAG AA (4.5:1) on its own soft background', () {
      double luminance(Color c) {
        // Color.r/g/b are already normalized 0..1 in this Flutter version.
        double channel(double v) {
          return v <= 0.03928
              ? v / 12.92
              : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        }

        return 0.2126 * channel(c.r) +
            0.7152 * channel(c.g) +
            0.0722 * channel(c.b);
      }

      double ratio(Color fg, Color bg) {
        final a = luminance(fg);
        final b = luminance(bg);
        final hi = a > b ? a : b;
        final lo = a > b ? b : a;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final tone in VynicStatusTone.values) {
        final t = VynicStatusTokens.ofTone(tone);
        expect(
          ratio(t.text, t.background),
          greaterThanOrEqualTo(4.5),
          reason: '$tone chip text fails WCAG AA on its soft background',
        );
      }
    });
  });

  group('Touch targets', () {
    test('POS floor is at least 44', () {
      expect(VynicTouchTargets.minPos, greaterThanOrEqualTo(44));
      expect(VynicTouchTargets.minRow, greaterThanOrEqualTo(44));
    });

    test('admin floor is at least 36', () {
      expect(VynicTouchTargets.minAdmin, greaterThanOrEqualTo(36));
    });
  });

  group('Motion', () {
    test('allowed durations are exactly 120ms and 200ms', () {
      expect(VynicMotion.allowed, [
        const Duration(milliseconds: 120),
        const Duration(milliseconds: 200),
      ]);
    });

    test('fast and normal are within the allowed set', () {
      expect(VynicMotion.allowed, contains(VynicMotion.fast));
      expect(VynicMotion.allowed, contains(VynicMotion.normal));
    });
  });

  group('Typography', () {
    test('no style drops below the 11px floor', () {
      final styles = <TextStyle>[
        VynicTextStyles.title,
        VynicTextStyles.heading,
        VynicTextStyles.bodyStrong,
        VynicTextStyles.body,
        VynicTextStyles.label,
        VynicTextStyles.caption,
      ];
      for (final style in styles) {
        expect(
          style.fontSize,
          greaterThanOrEqualTo(VynicTextStyles.minFontSize),
        );
      }
    });

    test('weights are restrained to 600/800', () {
      final weights = {
        VynicTextStyles.title.fontWeight,
        VynicTextStyles.heading.fontWeight,
        VynicTextStyles.bodyStrong.fontWeight,
        VynicTextStyles.label.fontWeight,
        VynicTextStyles.caption.fontWeight,
      };
      expect(weights, everyElement(isIn([FontWeight.w600, FontWeight.w800])));
    });
  });

  group('Breakpoints', () {
    test('maps target resolutions to the expected layout mode', () {
      // Common terminal/laptop widths (minus a little chrome is still >1100).
      expect(VynicBreakpoints.modeForWidth(1024), VynicLayoutMode.compact);
      expect(VynicBreakpoints.modeForWidth(1280), VynicLayoutMode.regular);
      expect(VynicBreakpoints.modeForWidth(1366), VynicLayoutMode.regular);
      expect(VynicBreakpoints.modeForWidth(1440), VynicLayoutMode.regular);
      expect(VynicBreakpoints.modeForWidth(1536), VynicLayoutMode.regular);
      expect(VynicBreakpoints.modeForWidth(1600), VynicLayoutMode.expanded);
      expect(VynicBreakpoints.modeForWidth(1920), VynicLayoutMode.expanded);
      expect(VynicBreakpoints.modeForWidth(2560), VynicLayoutMode.expanded);
    });
  });

  group('Responsive panel width rules', () {
    test('never below the min panel width on any target resolution', () {
      for (final w in [1024.0, 1280.0, 1366.0, 1440.0, 1920.0, 2560.0]) {
        final panel = VynicResponsive.panelWidth(w);
        expect(
          panel,
          greaterThanOrEqualTo(VynicResponsive.minPanelWidth - 0.01),
          reason: 'panel too narrow at width $w',
        );
      }
    });

    test('never wider than the max panel width', () {
      for (final w in [1280.0, 1600.0, 1920.0, 2560.0]) {
        final panel = VynicResponsive.panelWidth(w);
        expect(panel, lessThanOrEqualTo(VynicResponsive.maxPanelWidth + 0.01));
      }
    });

    test('panel never starves the primary pane (<=42% of width)', () {
      for (final w in [1280.0, 1366.0, 1920.0]) {
        expect(
          VynicResponsive.panelWidth(w),
          lessThanOrEqualTo(w * 0.42 + 0.01),
        );
      }
    });

    test('two panes are refused below the compact breakpoint', () {
      expect(VynicResponsive.canShowTwoPanes(1024), isFalse);
      expect(VynicResponsive.canShowTwoPanes(1366), isTrue);
    });
  });
}
