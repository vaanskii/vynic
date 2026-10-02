import 'dart:async';
import 'dart:io';

/// Unit/widget proofs use synthetic stores and explicit HTTP clients. Prevent
/// a missing mock from reaching an actual restaurant or configured backend.
class _NoExternalHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => throw StateError(
    'Synthetic test forbids actual HTTP; inject a mock client',
  );
}

Future<void> testExecutable(FutureOr<void> Function() main) async {
  HttpOverrides.global = _NoExternalHttp();
  await main();
}
