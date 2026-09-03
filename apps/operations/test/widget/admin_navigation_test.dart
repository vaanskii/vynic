import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/screens/admin_screen.dart';

/// Every admin tool has to be reachable by name from the sidebar.
///
/// Backup used to be a panel at the foot of „კავშირი" and reports had moved
/// out of Settings, which is how both came to look like they had been
/// deleted. These pin the destinations so a future reshuffle cannot quietly
/// bury one again.
void main() {
  test('the sidebar reaches every admin tool', () {
    const sections = AdminScreen.navigableSections;

    for (final section in const [
      'staff',
      'menu',
      'packages',
      'reservations',
      'tableLayouts',
      'display',
      'closeday',
      'sales',
      'salesReport',
      'financialReports',
      'audit',
      'errors',
      'printers',
      'connection',
      'settings',
    ]) {
      expect(sections, contains(section), reason: section);
    }
  });

  test('a venue manager sees the business tools and nothing else', () {
    // The line the app is sold across. A manager runs the restaurant: staff,
    // menu, floor, money. They do not get the terminal's plumbing, because a
    // guessed backend URL or printer port is a support call, and they do not
    // get the developer section, because it holds restore and wipe.
    for (final section in const [
      'staff',
      'menu',
      'packages',
      'reservations',
      'tableLayouts',
      'display',
      'closeday',
      'sales',
      'salesReport',
      'financialReports',
      'audit',
      'settings',
    ]) {
      expect(AdminScreen.managerSections, contains(section), reason: section);
    }

    for (final section in AdminScreen.developerSections) {
      expect(
        AdminScreen.managerSections,
        isNot(contains(section)),
        reason: section,
      );
    }
  });

  test('the developer half is exactly the plumbing and the danger tools', () {
    expect(
      AdminScreen.developerSections,
      containsAll(const ['errors', 'printers', 'connection', 'developer']),
    );
  });

  test('the exports are a destination of their own', () {
    // The monthly/full XLSX and PDF exports were buried twice — first under
    // Settings, then under the sales report — so they get their own entry.
    // Backup is deliberately not one: creating a copy is two buttons inside
    // Settings, and restoring one lives in the developer section.
    expect(AdminScreen.navigableSections, contains('financialReports'));
    expect(AdminScreen.navigableSections, contains('salesReport'));
    expect(AdminScreen.navigableSections, isNot(contains('backup')));
  });

  test('every destination has a title', () {
    for (final section in AdminScreen.navigableSections) {
      final title = AdminScreen.sectionTitle(section);
      expect(title, isNotEmpty, reason: section);
      expect(title, isNot('მართვის ცენტრი'), reason: section);
    }
  });
}
