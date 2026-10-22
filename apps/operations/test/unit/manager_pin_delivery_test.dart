import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/database/database_core.dart';
import 'package:vynic/core/database/repositories/user_repository.dart';
import 'package:vynic/core/models/user.dart';
import 'package:vynic/core/services/edge/pos_edge_command_handlers.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('isolated-manager-pin-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(UserAdapter());
    DatabaseCore.userBox = await Hive.openBox<User>('users');
    DatabaseCore.settingsBox = await Hive.openBox('settings');
    DatabaseCore.auditLogBox = await Hive.openBox('audit');
  });
  tearDown(() async {
    await Hive.close();
    DatabaseCore.userBox = null;
    DatabaseCore.settingsBox = null;
    DatabaseCore.auditLogBox = null;
    await directory.delete(recursive: true);
  });
  Future<void> user(String name, String pin) => DatabaseCore.userBox!.put(
    name,
    User(username: name, pinCode: pin, role: 'manager'),
  );
  Map<String, dynamic> command(
    int revision,
    String action, {
    String pin = '481259',
  }) => {
    'username': 'current',
    'pinCode': pin,
    'role': 'manager',
    'staffId': 'synthetic-staff',
    'platformAction': action,
    'platformRevision': revision,
  };
  test(
    'disabled legacy identity cannot block reset; delivery and watermark survive restart',
    () async {
      await user('legacy', '481259');
      await user('current', '924813');
      await UserRepository.setPlatformAccess('legacy', disabled: true);
      await UserRepository.setPlatformAccess('current', disabled: true);
      final payload = command(2, 'reset');
      expect((await const StaffCreateEdgeHandler().apply(payload)).ok, isTrue);
      expect(UserRepository.authenticateByPin('481259')?.username, 'current');
      expect((await const StaffCreateEdgeHandler().apply(payload)).ok, isTrue);
      await Hive.close();
      DatabaseCore.userBox = await Hive.openBox<User>('users');
      DatabaseCore.settingsBox = await Hive.openBox('settings');
      DatabaseCore.auditLogBox = await Hive.openBox('audit');
      expect(
        (await const StaffCreateEdgeHandler().apply(
          command(1, 'reset', pin: '924813'),
        )).code,
        'superseded',
      );
      expect(UserRepository.authenticateByPin('481259')?.username, 'current');
      expect(
        (await const StaffDeleteEdgeHandler().apply(command(3, 'disable'))).ok,
        isTrue,
      );
      expect(UserRepository.authenticateByPin('481259'), isNull);
      await const StaffCreateEdgeHandler().apply(payload);
      expect(UserRepository.authenticateByPin('481259'), isNull);
    },
  );
  test('active collision rejects delivery and remains retryable', () async {
    await user('other', '481259');
    await user('current', '924813');
    expect(
      (await const StaffCreateEdgeHandler().apply(command(2, 'reset'))).ok,
      isFalse,
    );
    expect(
      DatabaseCore.settingsBox!.get('platform_staff_revision:synthetic-staff'),
      isNull,
    );
    expect(UserRepository.authenticateByPin('924813')?.username, 'current');
    await UserRepository.setPlatformAccess('other', disabled: true);
    expect(
      (await const StaffCreateEdgeHandler().apply(command(2, 'reset'))).ok,
      isTrue,
    );
  });
  test(
    'ambiguous active local PIN fails closed, normal staff edit still works',
    () async {
      await user('one', '481259');
      await user('two', '481259');
      expect(UserRepository.authenticateByPin('481259'), isNull);
      expect(
        await UserRepository.updateUserPinByUsername(
          username: 'two',
          pinCode: '924813',
        ),
        isTrue,
      );
      expect(UserRepository.authenticateByPin('481259')?.username, 'one');
      expect(UserRepository.authenticateByPin('924813')?.username, 'two');
    },
  );
}
