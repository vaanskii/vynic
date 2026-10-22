import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/utils/home_reservations_helper.dart';
import 'seed.dart';
void main() {
  test('res', () async {
    Hive.init(Directory.systemTemp.createTempSync('vdbg').path);
    registerAll();
    await seedRestaurant('dbg', DateTime(2026, 9, 30));
    print('all=${DatabaseService.getAllReservations().length} cur=${DatabaseService.getCurrentDate()}');
    for (final r in DatabaseService.getAllReservations()) { print('${r.id} ${r.status} ${r.reservationDate} tk=${r.isTakeAway} notes=${r.notes}'); }
    print('panel=${HomeReservationsHelper.getAdminPanelReservations().length}');
  });
}
