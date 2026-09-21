/// Narrow opt-in for Windows release-mode development lab builds only.
/// Staging, production, Manager builds (without this define), and other origins
/// retain the normal HTTPS requirement.
bool permitsLocalLabApi(
  Uri uri, {
  required String environment,
  required bool enabled,
  required bool windows,
}) =>
    enabled &&
    windows &&
    environment == 'development' &&
    const {'http://10.10.10.3:3000', 'http://172.20.10.2:3000'}.contains(uri.toString());
