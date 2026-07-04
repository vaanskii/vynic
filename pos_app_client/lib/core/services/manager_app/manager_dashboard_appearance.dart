/// Dashboard visual mode persisted by [ManagerAppPreferences].
enum ManagerDashboardAppearance {
  light,
  dark;

  String get labelGeorgian => switch (this) {
    ManagerDashboardAppearance.light => 'ღია',
    ManagerDashboardAppearance.dark => 'მუქი',
  };
}
