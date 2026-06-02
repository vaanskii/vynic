part of '../mobile_admin_screen.dart';

/// Flat manager-console palette — no glass blur or decorative backgrounds.
abstract final class AdminTheme {
  static const bg = Color(0xFF0E1014);
  static const surface = Color(0xFF161920);
  static const surfaceElevated = Color(0xFF1C2029);
  static const border = Color(0xFF2E3440);
  static const primary = Color(0xFF4F46E5);
  static const accent = Color(0xFF3B82F6);
  static const good = Color(0xFF22C55E);
  static const bad = Color(0xFFEF4444);
  static const warn = Color(0xFFF59E0B);
  static const text = Color(0xFFF3F4F6);
  static const textMuted = Color(0xFF9CA3AF);
  static const textDim = Color(0xFF6B7280);
}

final NumberFormat _adminMoney = NumberFormat('#,##0.00', 'en_US');
String _adminGel(num v) => '₾${_adminMoney.format(v)}';

String _adminPaymentLabel(String key) {
  switch (key.trim().toLowerCase()) {
    case 'card-tbc':
      return 'ბარათი TBC';
    case 'card-bog':
      return 'ბარათი BOG';
    case 'cash':
      return 'ნაღდი';
    case 'non-fiscal':
    case 'nonfiscal':
    case 'non_fiscal':
      return 'არაფისკალური';
    default:
      return key;
  }
}

Color _adminPaymentColor(String key) {
  switch (key.trim().toLowerCase()) {
    case 'cash':
      return AdminTheme.good;
    case 'card-tbc':
    case 'card-bog':
      return AdminTheme.accent;
    case 'non-fiscal':
    case 'nonfiscal':
    case 'non_fiscal':
      return AdminTheme.warn;
    default:
      return AdminTheme.primary;
  }
}

String? _adminShareSubtitle(num part, num total) {
  if (total <= 0) return null;
  return '${(part / total * 100).toStringAsFixed(0)}%';
}

/// Clears the floating bottom nav when scrolling admin tabs.
EdgeInsets _adminScrollPadding(BuildContext context) {
  final bottom = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(16, 12, 16, bottom + 108);
}

void _adminToast(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AdminTheme.bad : AdminTheme.good,
      content: Text(msg),
    ),
  );
}

class _AdminLoading extends StatelessWidget {
  const _AdminLoading();

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: AdminTheme.primary, strokeWidth: 2.5),
      );
}

class _AdminOfflineBanner extends StatelessWidget {
  const _AdminOfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _AdminPanel(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      accentBorder: AdminTheme.warn.withValues(alpha: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AdminTheme.warn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AdminTheme.textMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTileSkeleton extends StatelessWidget {
  const _SettingsTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AdminTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 10,
                  width: 72,
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AdminTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: AdminTheme.textDim),
              const SizedBox(height: 14),
              const Text(
                'მონაცემები ვერ ჩაიტვირთა',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AdminTheme.text,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('თავიდან'),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Flat bordered block — no backdrop blur.
class _AdminPanel extends StatelessWidget {
  const _AdminPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.accentBorder,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? accentBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AdminTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentBorder ?? AdminTheme.border,
          width: accentBorder != null ? 1.5 : 1,
        ),
      ),
      child: child,
    );
  }
}

class _AdminSection extends StatelessWidget {
  const _AdminSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdminSectionTitle(title: title, trailing: trailing),
        child,
      ],
    );
  }
}

class _AdminSectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;

  const _AdminSectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 18,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AdminTheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: AdminTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textDim,
                ),
              ),
          ],
        ),
      );
}

class _AdminHeroMetric extends StatelessWidget {
  const _AdminHeroMetric({
    required this.label,
    required this.value,
    this.subtitle,
    this.accent = AdminTheme.good,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _AdminPanel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      accentBorder: accent.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: -1,
              height: 1.1,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 13, color: AdminTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String? subtitle;

  const _AdminStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AdminTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AdminTheme.text,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 11, color: AdminTheme.textDim),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMetricRow extends StatelessWidget {
  const _AdminMetricRow({
    required this.label,
    required this.value,
    this.color = AdminTheme.text,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AdminTheme.textMuted),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AdminFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AdminTheme.primary : AdminTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AdminTheme.primary : AdminTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AdminTheme.textMuted,
            ),
          ),
        ),
      );
}

class _AdminMonthNav extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _AdminMonthNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, size: 20, color: AdminTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AdminTheme.text,
              ),
            ),
          ),
          _AdminIconNavButton(icon: Icons.chevron_left_rounded, onTap: onPrev),
          const SizedBox(width: 8),
          _AdminIconNavButton(icon: Icons.chevron_right_rounded, onTap: onNext),
        ],
      ),
    );
  }
}

class _AdminIconNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AdminIconNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AdminTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: AdminTheme.text),
          ),
        ),
      );
}

class _AdminKpiGrid extends StatelessWidget {
  final List<_AdminKpiItem> items;

  const _AdminKpiGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (e) => SizedBox(
                  width: w,
                  child: _AdminStatCard(
                    label: e.label,
                    value: e.value,
                    icon: e.icon,
                    accent: e.color,
                    subtitle: e.subtitle,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _AdminKpiItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _AdminKpiItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });
}

class _AdminPrimaryButton extends StatelessWidget {
  const _AdminPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.add_rounded, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AdminTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

/// Connection dot only: green = ok, orange = API issue, red = offline.
class _AdminConnectionDot extends StatelessWidget {
  const _AdminConnectionDot({this.size = 11});

  final double size;

  static Color _color(bool connected, bool apiError) {
    if (!connected) return AdminTheme.bad;
    if (apiError) return AdminTheme.warn;
    return AdminTheme.good;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        MonitoringSocketService.isConnected,
        MonitoringSocketService.apiError,
      ]),
      builder: (_, __) {
        final dot = _color(
          MonitoringSocketService.isConnected.value,
          MonitoringSocketService.apiError.value,
        );
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: dot,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: dot.withValues(alpha: 0.55),
                blurRadius: 6,
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<bool?> _adminConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AdminTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AdminTheme.border),
      ),
      title: Text(title, style: const TextStyle(color: AdminTheme.text)),
      content: message == null
          ? null
          : Text(message, style: const TextStyle(color: AdminTheme.textMuted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('გაუქმება', style: TextStyle(color: AdminTheme.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('დიახ', style: TextStyle(color: AdminTheme.bad)),
        ),
      ],
    ),
  );
}

Future<bool?> _adminFormDialog(
  BuildContext context, {
  required String title,
  required List<Widget> fields,
  String confirm = 'შენახვა',
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AdminTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AdminTheme.border),
      ),
      title: Text(title, style: const TextStyle(color: AdminTheme.text)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: fields),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('გაუქმება', style: TextStyle(color: AdminTheme.textMuted)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AdminTheme.primary),
          child: Text(confirm),
        ),
      ],
    ),
  );
}

InputDecoration _adminInput(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AdminTheme.textMuted),
      filled: true,
      fillColor: AdminTheme.surfaceElevated,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AdminTheme.border),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AdminTheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
    );
