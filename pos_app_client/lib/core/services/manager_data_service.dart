import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/models/monitoring.dart';

class ManagerDataService {
  static ManagerDashboardMetrics getDashboardMetrics() {
    // Use business date instead of real-time clock
    final businessDate = DatabaseService.getCurrentDate();
    final todayStr = businessDate.toIso8601String().split('T')[0];
    
    final yesterday = businessDate.subtract(const Duration(days: 1));
    final yesterdayStr = yesterday.toIso8601String().split('T')[0];

    final todaySales = DatabaseService.getSalesForDate(todayStr);
    final yesterdaySales = DatabaseService.getSalesForDate(yesterdayStr);

    double todayRevenue = 0;
    for (var sale in todaySales) {
      if (sale['isCancelled'] == true) continue;
      todayRevenue += (sale['totalAmount'] ?? sale['total'] ?? 0.0);
    }

    double yesterdayRevenue = 0;
    for (var sale in yesterdaySales) {
      if (sale['isCancelled'] == true) continue;
      yesterdayRevenue += (sale['totalAmount'] ?? sale['total'] ?? 0.0);
    }

    final allOrders = DatabaseService.getAllOrders();
    final todayOrders = allOrders.where((o) {
      final orderDate = o.createdAt;
      return orderDate.year == businessDate.year && 
             orderDate.month == businessDate.month && 
             orderDate.day == businessDate.day;
    }).toList();

    final activeOrders = allOrders.where((o) => 
      o.status.toLowerCase() != 'closed' && 
      o.status.toLowerCase() != 'cancelled' && 
      o.status.toLowerCase() != 'paid'
    ).toList();

    final allTableNumbers = DatabaseService.getAllTableNumbers();
    final totalTables = allTableNumbers.length;
    
    double occupancy = totalTables > 0 ? (activeOrders.length / totalTables) * 100 : 0;

    return ManagerDashboardMetrics(
      todayRevenue: todayRevenue,
      closedTablesRevenue: todayRevenue,
      nonFiscalClosedRevenue: 0,
      todayOrderCount: todayOrders.length,
      activeTablesCount: activeOrders.length,
      openTablesAmount: activeOrders.fold<double>(
        0,
        (sum, order) => sum + order.totalAmount,
      ),
      openTablesPayable: activeOrders.fold<double>(
        0,
        (sum, order) => sum + order.totalAmount,
      ),
      occupancyPercentage: occupancy,
      yesterdayRevenue: yesterdayRevenue,
    );
  }

  static List<StaffMetric> getStaffPerformance() {
    final businessDate = DatabaseService.getCurrentDate();
    final todayStr = businessDate.toIso8601String().split('T')[0];
    final todaySales = DatabaseService.getSalesForDate(todayStr);
    
    final Map<String, List<double>> waiterSales = {};
    
    for (var sale in todaySales) {
      if (sale['isCancelled'] == true) continue;
      
      // Use createdBy or a specific waiter field if available
      final waiter = sale['createdBy'] ?? sale['waiter'] ?? 'პერსონალი';
      final amount = (sale['totalAmount'] ?? sale['total'] ?? 0.0);
      
      if (!waiterSales.containsKey(waiter)) {
        waiterSales[waiter] = [];
      }
      waiterSales[waiter]!.add(amount);
    }
    
    final List<StaffMetric> metrics = [];
    waiterSales.forEach((waiter, sales) {
      double total = 0;
      for (var s in sales) {
        total += s;
      }
      metrics.add(StaffMetric(
        waiterName: waiter,
        totalSales: total,
        orderCount: sales.length,
      ));
    });
    
    metrics.sort((a, b) => b.totalSales.compareTo(a.totalSales));
    return metrics;
  }
}
