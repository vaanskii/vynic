import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynic/core/database/local_data_admission.dart';
import 'package:vynic/core/database/repositories/audit_repository.dart';
import 'package:vynic/core/database/repositories/order_table_mutation_repository.dart';
import '../support/pos05_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Pos05Fixture fixture;
  late HttpOverrides? prior;
  setUp(() async {
    prior = HttpOverrides.current;
    root = await Directory.systemTemp.createTemp('vynic-pos05-boundaries-');
    fixture = Pos05Fixture();
    await fixture.open(root.path);
  });
  tearDown(() async {
    AuditRepository.registerAuditChangedCallback(() {});
    await fixture.close();
    HttpOverrides.global = prior;
    await root.delete(recursive: true);
  });
  for (final scenario in [
    'create',
    'takeaway',
    'package',
    'activation',
    'move',
    'cancel',
  ]) {
    test(
      '$scenario every actual put/flush boundary reopens and converges exactly once',
      () async {
        await fixture.prepare(scenario);
        await fixture.action();
        fixture.check();
        final boundaries = List<String>.of(fixture.trace);
        expect(boundaries, isNotEmpty);
        for (var position = 1; position <= boundaries.length; position++) {
          await fixture.close();
          final path = '${root.path}/$scenario-$position';
          await Directory(path).create();
          await fixture.open(path);
          await fixture.prepare(scenario);
          fixture.fault = (point, count) async {
            if (count == position) {
              expect(point, boundaries[position - 1]);
              throw const FileSystemException('synthetic write-boundary fault');
            }
          };
          await expectLater(
            fixture.action(),
            throwsA(anything),
            reason: '$position ${boundaries[position - 1]}',
          );
          await fixture.close();
          await fixture.open(path);
          if (OrderTableMutationRepository.read(fixture.id) == null)
            await fixture.action();
          fixture.check();
          final before = fixture.persisted();
          await OrderTableMutationRepository.recoverPending();
          await fixture.action();
          fixture.check();
          expect(
            fixture.persisted(),
            before,
            reason: '$scenario retry may not duplicate/reprice/release again',
          );
          expect(LocalDataAdmission.failure, isNull);
        }
      },
    );
  }
}
