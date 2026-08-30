import '../database_core.dart';
import 'sales_repository.dart';
import 'table_repository.dart';

/// Business-date handling for the POS.
///
/// The POS day is decoupled from the wall clock: `currentDate` in settings is
/// the operating date and only advances at close-day, not at midnight.
class BusinessDayRepository {
  BusinessDayRepository._();

  static const String _operatedBusinessDatesKey = 'operatedBusinessDates';

  static DateTime getCurrentDate() {
    final dateString = DatabaseCore.settingsBox!.get(
      'currentDate',
      defaultValue: DateTime.now().toIso8601String(),
    );
    return DateTime.parse(dateString as String);
  }

  static DateTime getCurrentDateTime() {
    final businessDate = getCurrentDate();
    final now = DateTime.now();
    return DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
  }

  static Future<void> setCurrentDate(DateTime newDate) async {
    final previousDate = getCurrentDate();
    await rememberOperatedBusinessDate(previousDate);
    await rememberOperatedBusinessDate(newDate);
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      newDate.toIso8601String(),
    );
    await TableRepository.syncTableReservationsForCurrentDate();
    await refreshDailySalesTotalForDate(newDate);
  }

  static List<String> getOperatedBusinessDateKeys() {
    final stored = DatabaseCore.settingsBox!.get(_operatedBusinessDatesKey);
    if (stored is List) {
      return stored
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  /// Persists [date] as an operated business day so empty days (without
  /// sales) still show up in business history.
  static Future<void> rememberOperatedBusinessDate(DateTime date) async {
    final dateKey = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().split('T')[0];
    final keys = getOperatedBusinessDateKeys();
    if (!keys.contains(dateKey)) {
      keys.add(dateKey);
      keys.sort();
      await DatabaseCore.settingsBox!.put(_operatedBusinessDatesKey, keys);
    }
  }

  static Future<void> refreshDailySalesTotalForDate(DateTime date) async {
    final dateString = date.toIso8601String().split('T')[0];
    final sales = SalesRepository.getSalesForDate(dateString);
    final total = sales
        .where(
          (sale) =>
              sale['isCancelled'] != true &&
              sale['restoredToOrder'] != true &&
              sale['isFiscal'] != false,
        )
        .fold<double>(
          0,
          (sum, sale) =>
              sum + ((sale['totalAmount'] as num?)?.toDouble() ?? 0.0),
        );
    final currentDateString = getCurrentDate().toIso8601String().split('T')[0];
    if (currentDateString == dateString) {
      await DatabaseCore.settingsBox!.put('dailySalesTotal', total);
    }
  }

  static List<DateTime> getOperatedBusinessDates() {
    final dates = <String>{
      ...getOperatedBusinessDateKeys(),
      getCurrentDate().toIso8601String().split('T')[0],
    };

    for (final sale in DatabaseCore.salesBox!.values) {
      final date = (sale as Map)['date'] as String?;
      if (date != null && date.isNotEmpty) {
        dates.add(date);
      }
    }

    final parsedDates = dates
        .where((date) => date.isNotEmpty)
        .map((date) => DateTime.parse(date))
        .toList();

    parsedDates.sort();
    return parsedDates;
  }

  static List<DateTime> getKnownBusinessDates() {
    final dates = <String>{getCurrentDate().toIso8601String().split('T')[0]};

    for (final sale in DatabaseCore.salesBox!.values) {
      final date = (sale as Map)['date'] as String?;
      if (date != null && date.isNotEmpty) {
        dates.add(date);
      }
    }

    for (final reservation in DatabaseCore.reservationBox!.values) {
      dates.add(reservation.reservationDate.toIso8601String().split('T')[0]);
    }

    final parsedDates = dates
        .where((date) => date.isNotEmpty)
        .map((date) => DateTime.parse(date))
        .toList();

    parsedDates.sort();
    return parsedDates;
  }

  static String getGeorgianFormattedDate(DateTime date) {
    final months = [
      'იანვარი',
      'თებერვალი',
      'მარტი',
      'აპრილი',
      'მაისი',
      'ივნისი',
      'ივლისი',
      'აგვისტო',
      'სექტემბერი',
      'ოქტომბერი',
      'ნოემბერი',
      'დეკემბერი',
    ];
    final weekDays = [
      'ორშაბათი',
      'სამშაბათი',
      'ოთხშაბათი',
      'ხუთშაბათი',
      'პარასკევი',
      'შაბათი',
      'კვირა',
    ];

    final day = date.day;
    final month = months[date.month - 1];
    final year = date.year;
    final weekDay = weekDays[date.weekday - 1];

    return '$weekDay, $day $month $year';
  }
}
