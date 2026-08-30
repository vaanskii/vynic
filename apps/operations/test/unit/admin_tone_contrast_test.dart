import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// The admin panel used to carry roughly seventy hand-picked hex codes across
/// fourteen sections. They now resolve to six semantic tones plus the shared
/// floor tokens, which is only an improvement if the pairs stay readable — a
/// tone is a *fill and a text colour together*, and it is easy to adjust one
/// and forget the other.

double _luminance(Color c) {
  double channel(double v) {
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _ratio(Color fg, Color bg) {
  final a = _luminance(fg);
  final b = _luminance(bg);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Admin tones', () {
    const tones = <String, AdminTone>{
      'success': AdminTones.success,
      'warning': AdminTones.warning,
      'danger': AdminTones.danger,
      'info': AdminTones.info,
      'accent': AdminTones.accent,
      'neutral': AdminTones.neutral,
    };

    test('every tone reads on its own fill at WCAG AA', () {
      for (final entry in tones.entries) {
        expect(
          _ratio(entry.value.text, entry.value.fill),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} text fails AA on its own fill',
        );
      }
    });

    test('every tone reads on a plain panel at WCAG AA', () {
      // Tone text is used bare as often as it is used on the matching fill —
      // a coloured figure on a white card, a tinted row label.
      for (final entry in tones.entries) {
        expect(
          _ratio(entry.value.text, VynicFloorTokens.panel),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} text fails AA on a panel',
        );
      }
    });

    test('a tone border is visible against the panel behind it', () {
      // The redesign separates cards with a hairline instead of a shadow, so a
      // border that fades into the page is a border that is not there.
      for (final entry in tones.entries) {
        expect(
          _ratio(entry.value.border, VynicFloorTokens.panel),
          greaterThan(1.02),
          reason: '${entry.key} border is invisible on a panel',
        );
      }
    });

    test('the tones are distinguishable from one another', () {
      // Six tones collapsed from seventy colours still have to be six.
      final seen = <int, String>{};
      for (final entry in tones.entries) {
        final key = entry.value.text.toARGB32();
        expect(
          seen.containsKey(key),
          isFalse,
          reason: '${entry.key} and ${seen[key]} share a text colour',
        );
        seen[key] = entry.key;
      }
    });
  });

  group('Admin chrome', () {
    test('body and muted text read on both panel surfaces', () {
      for (final surface in const [AdminDesign.panel, AdminDesign.panelSoft]) {
        expect(_ratio(AdminDesign.text, surface), greaterThanOrEqualTo(4.5));
        expect(_ratio(AdminDesign.muted, surface), greaterThanOrEqualTo(4.5));
      }
    });

    test('the primary button label reads on its own fill', () {
      // `accentDark` is the one filled button on a screen, and the theme puts
      // white on it.
      expect(
        _ratio(VynicFloorTokens.panel, AdminDesign.accentDark),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the accent is readable as a foreground, not just as a wash', () {
      // It replaced a saturated teal that call sites used both ways — bare as
      // a foreground, and tinted with `withValues(alpha:)` for a fill. A pale
      // tint here would have made every one of those foregrounds vanish.
      expect(
        _ratio(AdminDesign.accent, AdminDesign.panel),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _ratio(AdminDesign.accentDark, AdminDesign.accentSoft),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('danger reads on a panel and on its own soft fill', () {
      expect(
        _ratio(AdminDesign.danger, AdminDesign.panel),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _ratio(AdminDesign.danger, VynicFloorTokens.dangerFill),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the admin is built from the same tokens as the floor', () {
      // The point of the restyle: one palette, not two. If somebody
      // reintroduces a private hex here, these stop matching.
      expect(AdminDesign.surface, VynicFloorTokens.page);
      expect(AdminDesign.panel, VynicFloorTokens.panel);
      expect(AdminDesign.border, VynicFloorTokens.panelBorder);
      expect(AdminDesign.text, VynicFloorTokens.text);
      expect(AdminDesign.accentDark, VynicFloorTokens.accentStrong);
    });
  });
}
