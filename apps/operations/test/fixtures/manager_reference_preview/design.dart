import 'package:flutter/material.dart';

abstract final class D {
  static const ink = Color(0xFF282532);
  static const muted = Color(0xFF6E6A78);
  static const purple = Color(0xFF7052AD);
  static const purpleLight = Color(0xFFF0EBF8);
  static const bg = Color(0xFFF6F5F8);
  static const line = Color(0xFFE9E6ED);
  static const green = Color(0xFF33735E);
  static const greenLight = Color(0xFFEDF5F1);
  static const amber = Color(0xFF91632A);
  static const amberLight = Color(0xFFFBF3E7);
  static const red = Color(0xFFA33D4C);
  static const r = 16.0;
}

TextStyle ts(
  double size, {
  Color color = D.ink,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'NotoSansGeorgian',
  fontSize: size,
  height: 1.42,
  color: color,
  fontWeight: weight,
);
Widget txt(
  String s, {
  double size = 14,
  Color color = D.ink,
  FontWeight weight = FontWeight.w400,
  int? lines,
  TextAlign? align,
}) => Text(
  s,
  style: ts(size, color: color, weight: weight),
  maxLines: lines,
  overflow: lines == null ? null : TextOverflow.ellipsis,
  textAlign: align,
);
Widget gap([double h = 16]) => SizedBox(height: h);
Widget hgap([double w = 12]) => SizedBox(width: w);
ThemeData previewTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSansGeorgian',
  scaffoldBackgroundColor: D.bg,
  colorScheme: const ColorScheme.light(
    primary: D.purple,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: D.ink,
    error: D.red,
    outline: D.line,
  ),
  dividerColor: D.line,
  dividerTheme: const DividerThemeData(color: D.line, thickness: 1),
  splashFactory: NoSplash.splashFactory,
  tooltipTheme: TooltipThemeData(textStyle: ts(12, color: Colors.white)),
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: D.purple,
    selectionColor: D.purple.withValues(alpha: .2),
    selectionHandleColor: D.purple,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    hintStyle: ts(14, color: D.muted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: D.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: D.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: D.purple, width: 2),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: D.purple,
      foregroundColor: Colors.white,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: ts(13, weight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: D.ink,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      textStyle: ts(13, weight: FontWeight.w500),
      side: const BorderSide(color: D.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: D.purple,
      minimumSize: const Size(44, 44),
      textStyle: ts(13, weight: FontWeight.w600),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: D.muted,
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
);

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = 24,
    this.color = Colors.white,
  });
  final Widget child;
  final double padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(D.r),
      side: const BorderSide(color: D.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class Badge extends StatelessWidget {
  const Badge(
    this.label, {
    super.key,
    this.color = D.green,
    this.bg = D.greenLight,
    this.dot = true,
  });
  final String label;
  final Color color, bg;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          hgap(6),
        ],
        Flexible(
          child: txt(label, size: 11, color: color, weight: FontWeight.w500),
        ),
      ],
    ),
  );
}

class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.sub, this.action, this.onTap});
  final String title;
  final String? sub, action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              txt(title, size: 16, weight: FontWeight.w600),
              if (sub != null) ...[gap(3), txt(sub!, size: 12, color: D.muted)],
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                txt(
                  action!,
                  size: 12,
                  color: D.purple,
                  weight: FontWeight.w600,
                ),
                hgap(5),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
      ],
    ),
  );
}

class ActionButton extends StatelessWidget {
  const ActionButton(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.primary = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), hgap(8)],
        Flexible(child: Text(label)),
      ],
    );
    return primary
        ? FilledButton(onPressed: onTap, child: child)
        : OutlinedButton(onPressed: onTap, child: child);
  }
}

class Segments extends StatelessWidget {
  const Segments(
    this.labels, {
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEECF1),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: List.generate(
          labels.length,
          (i) => TextButton(
            style: TextButton.styleFrom(
              backgroundColor: i == selected
                  ? Colors.white
                  : Colors.transparent,
              foregroundColor: i == selected ? D.ink : D.muted,
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => onSelect(i),
            child: Text(
              labels[i],
              style: ts(
                12,
                color: i == selected ? D.ink : D.muted,
                weight: i == selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class KV extends StatelessWidget {
  const KV(this.label, this.value, {super.key, this.emphasis = false});
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: txt(label, size: 13, color: D.muted)),
        hgap(),
        Flexible(
          child: txt(
            value,
            size: emphasis ? 19 : 13,
            weight: emphasis ? FontWeight.w600 : FontWeight.w500,
            align: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

class PreviewNote extends StatelessWidget {
  const PreviewNote({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.science_outlined, size: 13, color: D.muted),
      hgap(5),
      txt('დიზაინის პრევიუ · სინთეტიკური მონაცემები', size: 10, color: D.muted),
    ],
  );
}
