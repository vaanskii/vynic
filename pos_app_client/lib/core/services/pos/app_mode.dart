class AppMode {
  AppMode._();

  static bool? printHostOverride;

  static bool get isPrintHost => printHostOverride ?? true;
}
