class ManagerDashboardMetrics {
  final double todayRevenue;
  final double shiftTotalRevenue;
  final double closedTablesRevenue;
  final double nonFiscalClosedRevenue;
  final int todayOrderCount;
  final int activeTablesCount;
  final double openTablesAmount;
  final double openTablesPayable;
  final double occupancyPercentage;
  final double yesterdayRevenue;
  final String? businessDate;
  final String? businessDayId;
  final String businessDayStatus;
  final String? businessDayOpenedAt;
  final int? businessDayDurationMinutes;
  final double cashRevenue;
  final double cardRevenue;
  final double refunds;
  final int totalTables;
  final int occupiedTables;
  final int reservedTables;
  final int freeTables;

  ManagerDashboardMetrics({
    required this.todayRevenue,
    double? shiftTotalRevenue,
    required this.closedTablesRevenue,
    required this.nonFiscalClosedRevenue,
    required this.todayOrderCount,
    required this.activeTablesCount,
    required this.openTablesAmount,
    required this.openTablesPayable,
    required this.occupancyPercentage,
    required this.yesterdayRevenue,
    this.businessDate,
    this.businessDayId,
    this.businessDayStatus = 'OPEN',
    this.businessDayOpenedAt,
    this.businessDayDurationMinutes,
    this.cashRevenue = 0,
    this.cardRevenue = 0,
    this.refunds = 0,
    this.totalTables = 0,
    this.occupiedTables = 0,
    this.reservedTables = 0,
    this.freeTables = 0,
  }) : shiftTotalRevenue = shiftTotalRevenue ??
            (todayRevenue + openTablesPayable);

  factory ManagerDashboardMetrics.fromJson(Map<String, dynamic> json) {
    final closed = (json['closedTablesRevenue'] ?? json['todayRevenue'] ?? 0)
        .toDouble();
    final open = (json['openTablesPayable'] ?? json['openTablesAmount'] ?? 0)
        .toDouble();
    return ManagerDashboardMetrics(
      todayRevenue: (json['todayRevenue'] ?? 0).toDouble(),
      shiftTotalRevenue:
          (json['shiftTotalRevenue'] ?? (closed + open)).toDouble(),
      closedTablesRevenue: closed,
      nonFiscalClosedRevenue: (json['nonFiscalClosedRevenue'] ?? 0).toDouble(),
      todayOrderCount: json['todayOrderCount'] ?? 0,
      activeTablesCount: json['activeTablesCount'] ?? 0,
      openTablesAmount: (json['openTablesAmount'] ?? 0).toDouble(),
      openTablesPayable:
          (json['openTablesPayable'] ?? json['openTablesAmount'] ?? 0)
              .toDouble(),
      occupancyPercentage: (json['occupancyPercentage'] ?? 0).toDouble(),
      yesterdayRevenue: (json['yesterdayRevenue'] ?? 0).toDouble(),
      businessDate: json['businessDate'] as String?,
      businessDayId: (json['businessDayId'] ?? json['businessDate']) as String?,
      businessDayStatus: (json['businessDayStatus'] ?? 'OPEN') as String,
      businessDayOpenedAt: json['businessDayOpenedAt'] as String?,
      businessDayDurationMinutes: json['businessDayDurationMinutes'] as int?,
      cashRevenue: (json['cashRevenue'] ?? 0).toDouble(),
      cardRevenue: (json['cardRevenue'] ?? 0).toDouble(),
      refunds: (json['refunds'] ?? 0).toDouble(),
      totalTables: json['totalTables'] ?? 0,
      occupiedTables: json['occupiedTables'] ?? 0,
      reservedTables: json['reservedTables'] ?? 0,
      freeTables: json['freeTables'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'todayRevenue': todayRevenue,
        'shiftTotalRevenue': shiftTotalRevenue,
        'closedTablesRevenue': closedTablesRevenue,
        'nonFiscalClosedRevenue': nonFiscalClosedRevenue,
        'todayOrderCount': todayOrderCount,
        'activeTablesCount': activeTablesCount,
        'openTablesAmount': openTablesAmount,
        'openTablesPayable': openTablesPayable,
        'occupancyPercentage': occupancyPercentage,
        'yesterdayRevenue': yesterdayRevenue,
        'businessDate': businessDate,
        'businessDayId': businessDayId,
        'businessDayStatus': businessDayStatus,
        'businessDayOpenedAt': businessDayOpenedAt,
        'businessDayDurationMinutes': businessDayDurationMinutes,
        'cashRevenue': cashRevenue,
        'cardRevenue': cardRevenue,
        'refunds': refunds,
        'totalTables': totalTables,
        'occupiedTables': occupiedTables,
        'reservedTables': reservedTables,
        'freeTables': freeTables,
      };
}

class StaffMetric {
  final String waiterName;
  final double totalSales;
  final int orderCount;

  StaffMetric({
    required this.waiterName,
    required this.totalSales,
    required this.orderCount,
  });

  factory StaffMetric.fromJson(Map<String, dynamic> json) {
    return StaffMetric(
      waiterName: json['waiterName'] ?? '',
      totalSales: (json['totalSales'] ?? 0).toDouble(),
      orderCount: json['orderCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'waiterName': waiterName,
        'totalSales': totalSales,
        'orderCount': orderCount,
      };
}
