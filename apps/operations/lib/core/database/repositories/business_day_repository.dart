import 'package:vynic/core/services/audit/money_audit.dart';

import '../database_core.dart';
import 'sales_repository.dart';
import 'table_repository.dart';

/// Why a business-date change was refused.
enum BusinessDateChangeOutcome {
  changed,

  /// Target is the date already being operated — nothing to do, nothing
  /// recorded.
  unchanged,

  /// Moving off the operating date without saying why.
  reasonRequired,

  /// The target is earlier than the date being operated, which re-opens a
  /// period the restaurant has already closed and reported. Support work,
  /// gated on the `backdate` developer scope.
  backdateNotPermitted,
}

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

  static String dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day).toIso8601String().split('T')[0];

  /// Moves the POS onto a different operating date.
  ///
  /// This is not a display setting. Every order, sale and expense recorded
  /// afterwards is filed under [newDate], so moving the date rewrites which
  /// day the restaurant's next hour of trading belongs to. It therefore takes
  /// a named actor and a stated [reason], and writes both to the audit log.
  ///
  /// Moving *backwards* — onto a day already closed and reported — additionally
  /// needs [allowBackdate], which only a caller holding the support scope may
  /// pass. Close-day does not come through here: it advances `currentDate`
  /// directly as part of its own transaction.
  static Future<BusinessDateChangeOutcome> setCurrentDate(
    DateTime newDate, {
    required String actorId,
    String reason = '',
    bool allowBackdate = false,
  }) async {
    final previousDate = getCurrentDate();
    final previousKey = dateKey(previousDate);
    final newKey = dateKey(newDate);
    if (previousKey == newKey) {
      return BusinessDateChangeOutcome.unchanged;
    }

    final trimmedReason = reason.trim();
    final actor = actorId.trim();
    if (trimmedReason.isEmpty || actor.isEmpty) {
      return BusinessDateChangeOutcome.reasonRequired;
    }

    final isBackdate = newKey.compareTo(previousKey) < 0;
    if (isBackdate && !allowBackdate) {
      return BusinessDateChangeOutcome.backdateNotPermitted;
    }

    await rememberOperatedBusinessDate(previousDate);
    await rememberOperatedBusinessDate(newDate);
    await DatabaseCore.settingsBox!.put(
      'currentDate',
      newDate.toIso8601String(),
    );
    await TableRepository.syncTableReservationsForCurrentDate();
    await refreshDailySalesTotalForDate(newDate);

    await MoneyAudit.businessDateChanged(
      actorId: actor,
      previousDate: previousKey,
      newDate: newKey,
      reason: trimmedReason,
      backdated: isBackdate,
    );

    return BusinessDateChangeOutcome.changed;
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

  /// The one author of `dailySalesTotal`.
  ///
  /// It used to have two: `saveSaleRecord` incremented it and this recomputed
  /// it, so the stored figure was whichever ran last and could drift from the
  /// records it claimed to summarize. The increment is gone; this derives the
  /// total from the sales box every time, using the same
  /// `SalesRepository.countsAsRevenue` predicate every other revenue figure
  /// uses.
  ///
  /// The figure is *gross* sales — an order settled partly by a deposit is
  /// worth what the guest consumed, not what was handed over at the table.
  /// Money actually taken today is a different question, answered by
  /// [collectedTotalForDate].
  static Future<void> refreshDailySalesTotalForDate(DateTime date) async {
    final dateString = dateKey(date);
    final total = grossSalesTotalForDate(dateString);
    final currentDateString = dateKey(getCurrentDate());
    if (currentDateString == dateString) {
      await DatabaseCore.settingsBox!.put('dailySalesTotal', total);
    }
  }

  /// Gross sales recorded against [dateString], derived from the records.
  static double grossSalesTotalForDate(String dateString) {
    final sales = SalesRepository.getSalesForDate(dateString);
    return _round(
      sales
          .where(SalesRepository.countsAsRevenue)
          .fold<double>(0, (sum, sale) => sum + SalesRepository.grossOf(sale)),
    );
  }

  /// Money that actually changed hands on [dateString].
  ///
  /// Tender lines on the day's sales, plus advances collected on the day, and
  /// deliberately *not* the advance applied to a sale closed today — that
  /// money was taken on some earlier day and counted there.
  static double collectedTotalForDate(String dateString) {
    final sales = SalesRepository.getSalesForDate(dateString);
    var collected = 0.0;
    for (final sale in sales) {
      if (sale['isCancelled'] == true) continue;
      if (sale['restoredToOrder'] == true) continue;
      if (SalesRepository.isAdvanceReceipt(sale)) {
        collected += (sale['totalAmount'] as num?)?.toDouble() ?? 0.0;
        continue;
      }
      if (!SalesRepository.isSaleRecord(sale)) continue;
      if (sale['isFiscal'] == false) continue;
      final stored = (sale['collectedNow'] as num?)?.toDouble();
      collected +=
          stored ??
          ((sale['totalAmount'] as num?)?.toDouble() ??
              (sale['total'] as num?)?.toDouble() ??
              0.0);
    }
    return _round(collected);
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;

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
