part of '../live_status_screen.dart';

extension _LiveStatusTablesView on _LiveStatusScreenState {
  Future<void> _showForceFreDialog(TableModel table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('მაგიდა ${table.tableNumber} — გათავისუფლება'),
        content: const Text(
          'ეს მაგიდა ბაზაში დაკავებულად არის მონიშნული. დარწმუნებული ხართ, რომ გსურთ მისი გათავისუფლება?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('გაუქმება'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('გათავისუფლება'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await MobileApiService.freeTable(table.tableNumber, table.floor);
    if (!mounted) return;

    _showStatusToast(
      ok ? 'მაგიდა ${table.tableNumber} გათავისუფლდა' : 'შეცდომა — ვერ მოხდა გათავისუფლება',
      isError: !ok,
      icon: ok ? Icons.table_restaurant_rounded : Icons.error_outline_rounded,
    );

    if (ok) _loadTables();
  }

  /// 'free' | 'occupied' | 'reserved'
  String _tableState(TableModel t) {
    if (t.activeOrderId != null) return 'occupied';
    if (t.isReserved) return 'reserved';
    return 'free';
  }

  bool _matchesFilter(TableModel t) {
    switch (_tableFilter) {
      case 1:
        return _tableState(t) == 'free';
      case 2:
        return _tableState(t) == 'occupied';
      case 3:
        return _tableState(t) == 'reserved';
      default:
        return true;
    }
  }

  String _elapsedShort(DateTime? since) {
    if (since == null) return '';
    final d = DateTime.now().difference(since);
    if (d.inMinutes < 1) return 'ახლახ';
    if (d.inMinutes < 60) return '${d.inMinutes}წთ';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}სთ' : '${h}სთ ${m}წთ';
  }

  Widget _buildTablesView() {
    if (_tablesLoading && _tablesByFloor.isEmpty) return _buildSkeletonLoader();
    if (_tablesByFloor.isEmpty) {
      return _buildTablesEmpty('მაგიდები ვერ მოიძებნა');
    }

    final sections = <Widget>[];
    for (final floor in _tablesByFloor.keys) {
      final filtered = _tablesByFloor[floor]!.where(_matchesFilter).toList();
      if (filtered.isEmpty) continue;
      sections.add(_buildFloorSection(floor, filtered));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 130),
      children: [
        _buildFilterPills(),
        const SizedBox(height: 18),
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text(
                'ამ ფილტრში მაგიდები არ არის',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            ),
          )
        else
          ...sections,
      ],
    );
  }

  Widget _buildTablesEmpty(String label) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.only(top: 120),
      children: [
        Icon(Icons.table_bar_outlined,
            size: 64, color: Colors.white.withOpacity(0.25)),
        const SizedBox(height: 16),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPills() {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _LiveStatusScreenState._tableFilters.length,
        itemBuilder: (context, index) {
          final isSel = _tableFilter == index;
          return GestureDetector(
            onTap: () => _setTableFilter(index),
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSel ? _kAccent : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSel ? _kAccent : Colors.white.withOpacity(0.1),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _LiveStatusScreenState._tableFilters[index],
                style: TextStyle(
                  color:
                      isSel ? Colors.white : Colors.white.withOpacity(0.7),
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const SizedBox(height: 38),
        const SizedBox(height: 18),
        for (var s = 0; s < 2; s++) ...[
          Container(
            width: 90,
            height: 14,
            margin: const EdgeInsets.only(bottom: 14, left: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.0,
            children: List.generate(
              4,
              (i) => Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildFloorSection(String floorName, List<TableModel> tables) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            floorName.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.5),
              letterSpacing: 1.2,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 900 ? 4 : width >= 640 ? 3 : 2;
            final aspect = width >= 640 ? 1.05 : 0.92;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: aspect,
              ),
              itemCount: tables.length,
              itemBuilder: (context, index) => _buildTableCard(tables[index]),
            );
          },
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  void _showReservedNoOrderSheet(TableModel table) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF15151C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kReserved.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_seat_rounded,
                  size: 36, color: _kReserved),
            ),
            const SizedBox(height: 14),
            Text(
              'მაგიდა ${table.tableNumber}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ეს მაგიდა დაჯავშნულია, მაგრამ შეკვეთა ჯერ არ გახსნილა.',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('დახურვა',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// Free-table tap → walk-in flow: pick menu items, then immediately create a
  /// confirmed dine-in order on this exact table (no table picker needed).
  Future<void> _startWalkInForTable(TableModel table) async {
    final selected = await Navigator.of(context).push<List<MenuSelectionLine>>(
      MaterialPageRoute(
        builder: (_) => const MobileCalculatorScreen(selectionMode: true),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    _showStatusToast(
      'მაგიდა ${table.tableNumber} — walk-in იქმნება...',
      icon: Icons.directions_walk_rounded,
    );
    try {
      final items = selected
          .map(
            (e) => <String, dynamic>{
              'itemName': e.itemName,
              'unitPrice': e.unitPrice,
              'quantity': e.qty,
            },
          )
          .toList();
      await MobileApiService.createWalkInOrder(
        tableNumbers: [table.tableNumber],
        floor: table.floor,
        waiterName: widget.user.username,
        items: items,
      );
      if (!mounted) return;
      _showStatusToast(
        'Walk-in შეიქმნა — მაგიდა ${table.tableNumber}',
        icon: Icons.check_circle_outline_rounded,
      );
      _loadTables();
    } catch (_) {
      if (!mounted) return;
      _showStatusToast('walk-in ვერ შეიქმნა', isError: true);
    }
  }

  Widget _buildTableCard(TableModel table) {
    final state = _tableState(table);
    final bool hasOrder = table.activeOrderId != null;
    final bool isOccupied = state == 'occupied';
    final bool isReserved = state == 'reserved';
    final double bill = table.currentBill ?? 0.0;

    final Color accent = isOccupied
        ? _kOccupied
        : isReserved
            ? _kReserved
            : _kFree;
    final IconData icon = isOccupied
        ? Icons.local_dining_rounded
        : isReserved
            ? Icons.schedule_rounded
            : Icons.chair_alt_rounded;

    final elapsed = _elapsedShort(table.reservedAt);

    return _GlassPanel(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.all(16),
      borderColor: state == 'free'
          ? Colors.white.withOpacity(0.08)
          : accent.withOpacity(0.45),
      borderWidth: state == 'free' ? 1 : 1.5,
      onTap: hasOrder
          ? () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MobileOrderDetailScreen(
                    user: widget.user,
                    orderId: table.activeOrderId!,
                    tableNumber: table.tableNumber,
                    floor: table.floor,
                  ),
                ),
              );
              if (result != null) _loadTables();
            }
          : isReserved
              ? () => _showReservedNoOrderSheet(table)
              : () => _startWalkInForTable(table),
      onLongPress:
          (isOccupied || isReserved) ? () => _showForceFreDialog(table) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'T-${table.tableNumber}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 14),
              ),
            ],
          ),
          if (isOccupied)
            Text(
              '${bill.toStringAsFixed(1)} ₾',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 21,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            )
          else
            Text(
              isReserved ? 'რეზერვი' : 'თავისუფალი',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          Row(
            children: [
              if (isOccupied || isReserved) ...[
                Icon(Icons.person_rounded,
                    size: 14, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    (table.reservedBy != null &&
                            table.reservedBy!.trim().isNotEmpty)
                        ? table.reservedBy!
                        : 'პერსონალი',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (elapsed.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    elapsed,
                    style: TextStyle(
                      color: isOccupied
                          ? Colors.white.withOpacity(0.5)
                          : accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ] else ...[
                Icon(Icons.add_circle_outline_rounded,
                    size: 14, color: _kFree.withOpacity(0.9)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'walk-in',
                    style: TextStyle(
                      color: _kFree.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
