import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vynic/core/services/pos/pos_locale.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';

/// Always-visible business date, distinct from the wall-clock time.
class PosWorkDate extends StatefulWidget {
  const PosWorkDate({
    super.key,
    required this.date,
    this.now,
    this.dark = false,
  });
  final DateTime date;
  final DateTime? now;
  final bool dark;
  @override
  State<PosWorkDate> createState() => _PosWorkDateState();
}

class _PosWorkDateState extends State<PosWorkDate> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = widget.now ?? DateTime.now();
    final date =
        '${widget.date.day.toString().padLeft(2, '0')}.${widget.date.month.toString().padLeft(2, '0')}.${widget.date.year}';
    final color = widget.dark ? Colors.white : VynicFloorTokens.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${PosLocale.tr(context, 'სამუშაო თარიღი')}: $date',
          key: const ValueKey('pos-work-date'),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('HH:mm').format(time),
          key: const ValueKey('pos-current-time'),
          textAlign: TextAlign.right,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
