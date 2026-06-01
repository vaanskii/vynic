import 'package:hive/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 0)
class User extends HiveObject {
  @HiveField(0)
  String username;

  @HiveField(1)
  String pinCode;

  @HiveField(2)
  String role; // 'admin' | 'manager' | 'waiter'

  User({required this.username, required this.pinCode, required this.role});

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager' || role == 'admin';
  bool get isWaiter => role == 'waiter';
}
