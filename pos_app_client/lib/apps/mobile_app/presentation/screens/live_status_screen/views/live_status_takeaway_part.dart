part of '../live_status_screen.dart';

extension _LiveStatusTakeawayView on _LiveStatusScreenState {
  Future<void> _cancelTakeawayOrder(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'შეკვეთის გაუქმება',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'გატანის შეკვეთა #${order.orderId} (${order.totalAmount.toStringAsFixed(2)} ₾) გაუქმდება.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('უკან'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('გაუქმება'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await MobileApiService.cancelOrder(order.orderId);
      if (!mounted) return;
      _showStatusToast('შეკვეთა გაუქმებულია');
      _loadTakeaway();
    } catch (e) {
      if (!mounted) return;
      _showStatusToast('შეცდომა: $e', isError: true);
    }
  }

  Future<void> _deleteTakeawayOrder(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'შეკვეთის წაშლა',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'გატანის შეკვეთა #${order.orderId} სრულად წაიშლება ბაზიდან და ვინდოუს აპიდანაც. ეს ქმედება შეუქცევადია.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('უკან'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('წაშლა'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await MobileApiService.deleteTakeawayOrder(order.orderId);
      if (!mounted) return;
      _showStatusToast('შეკვეთა წაშლილია');
      _loadTakeaway();
    } catch (e) {
      if (!mounted) return;
      _showStatusToast('შეცდომა: $e', isError: true);
    }
  }

  Widget _buildTakeawayView() {
    if (_takeawayLoading && _takeawayOrders.isEmpty) {
      return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        itemCount: 4,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
        ),
      );
    }

    if (_takeawayOrders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(top: 110),
        children: [
          Icon(Icons.takeout_dining_outlined,
              size: 72, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'გატანის შეკვეთები არ არის',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 130),
      itemCount: _takeawayOrders.length,
      itemBuilder: (context, index) => _buildTakeawayCard(_takeawayOrders[index]),
    );
  }

  bool _isFinalizedStatus(String status) {
    final s = status.toLowerCase();
    return s == 'paid' || s == 'cancelled' || s == 'closed';
  }

  Widget _buildTakeawayCard(Order order) {
    final isFinalized = _isFinalizedStatus(order.status);
    final statusColor = _takeawayStatusColor(order.status);
    final statusLabel = _takeawayStatusLabel(order.status);
    final displayedItems = isFinalized ? order.items : order.items.take(4).toList();
    final extraItemCount = (!isFinalized && order.items.length > 4)
        ? order.items.fold(0, (s, it) => s + it.quantity) -
            order.items.take(4).fold(0, (s, it) => s + it.quantity)
        : 0;

    Future<void> openDetails() async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MobileOrderDetailScreen(
            user: widget.user,
            orderId: order.orderId,
            tableNumber: 'Takeaway',
            floor: 'takeaway',
          ),
        ),
      );
      if (result != null) _loadTakeaway();
    }

    return Opacity(
      opacity: isFinalized ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: _GlassPanel(
          borderRadius: BorderRadius.circular(22),
          onTap: openDetails,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: _kAccent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.takeout_dining_rounded,
                        color: _kAccent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'გატანა #${order.orderId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            order.createdBy.isNotEmpty
                                ? order.createdBy
                                : 'პერსონალი',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${order.totalAmount.toStringAsFixed(2)} ₾',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _lightenStatus(statusColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (order.customerName.isNotEmpty ||
                    order.pickupTime.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (order.customerName.isNotEmpty) ...[
                        Icon(Icons.person_rounded,
                            size: 13, color: Colors.white.withOpacity(0.5)),
                        const SizedBox(width: 4),
                        Text(
                          order.customerName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                      if (order.customerName.isNotEmpty &&
                          order.pickupTime.isNotEmpty)
                        const SizedBox(width: 12),
                      if (order.pickupTime.isNotEmpty) ...[
                        Icon(Icons.access_time_rounded,
                            size: 13, color: Colors.white.withOpacity(0.5)),
                        const SizedBox(width: 4),
                        Text(
                          order.pickupTime,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (order.items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: displayedItems.map((it) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${it.quantity}× ${it.itemName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (extraItemCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '+$extraItemCount სხვა',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ),
                ],
                if (!isFinalized) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _takeawayActionButton(
                          label: 'გაუქმება',
                          icon: Icons.cancel_outlined,
                          color: const Color(0xFFEF4444),
                          onTap: () => _cancelTakeawayOrder(order),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _takeawayActionButton(
                          label: 'დეტალები',
                          icon: Icons.visibility_rounded,
                          color: _kAccent,
                          filled: true,
                          onTap: openDetails,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _takeawayIconButton(
                        icon: Icons.delete_outline_rounded,
                        onTap: () => _deleteTakeawayOrder(order),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => _deleteTakeawayOrder(order),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 16, color: Colors.white.withOpacity(0.45)),
                          const SizedBox(width: 4),
                          Text(
                            'წაშლა',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _takeawayActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled ? color : color.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: filled ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: filled ? Colors.white : color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _takeawayIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Icon(icon, size: 18, color: Colors.white.withOpacity(0.55)),
      ),
    );
  }

  /// Status colors are tuned for light bg; brighten slightly for dark chips.
  Color _lightenStatus(Color c) {
    return Color.alphaBlend(Colors.white.withOpacity(0.35), c);
  }

  Color _takeawayStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'preparing':
        return const Color(0xFF2563EB);
      case 'served':
        return const Color(0xFF7C3AED);
      case 'paid':
      case 'closed':
        return const Color(0xFF047857);
      case 'cancelled':
        return const Color(0xFF9F1239);
      case 'pending':
      default:
        return const Color(0xFFB45309);
    }
  }

  String _takeawayStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return 'დადასტურებული';
      case 'preparing':
        return 'მომზადება';
      case 'served':
        return 'მირთმეული';
      case 'paid':
      case 'closed':
        return 'დასრულებული';
      case 'cancelled':
        return 'გაუქმებული';
      case 'pending':
      default:
        return 'მოლოდინში';
    }
  }
}
