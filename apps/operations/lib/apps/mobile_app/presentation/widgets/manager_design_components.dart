import 'package:flutter/material.dart';
import '../../theme/manager_theme.dart';

// Composition and typography ported from the approved Manager experiment's
// design.dart. Colors resolve through the existing light/dark Manager palette.
TextStyle managerDesignText(
  BuildContext context,
  double size, {
  bool muted = false,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: 'NotoSansGeorgian',
  fontSize: size,
  height: 1.42,
  color: muted
      ? managerThemeOf(context).textSecondary
      : managerThemeOf(context).textPrimary,
  fontWeight: weight,
);

class ManagerPanel extends StatelessWidget {
  const ManagerPanel({
    super.key,
    required this.child,
    this.padding = 24,
    this.muted = false,
  });
  final Widget child;
  final double padding;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    return Material(
      color: muted ? t.scaffoldBackground : t.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}

class ManagerSectionHeading extends StatelessWidget {
  const ManagerSectionHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.action,
    this.onAction,
  });
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: managerDesignText(context, 16, weight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: managerDesignText(context, 12, muted: true),
              ),
            ],
          ],
        );
        final button = action == null
            ? null
            : TextButton(
                onPressed: onAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        action!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: managerThemeOf(context).primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              );
        // Long Georgian actions must not squeeze a heading into a narrow column.
        final stacked =
            button != null &&
            action!.length > 14 &&
            constraints.maxWidth <
                520 * MediaQuery.textScalerOf(context).scale(1);
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 8), button],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  if (button != null) button,
                ],
              );
      },
    ),
  );
}

class ManagerSegments extends StatelessWidget {
  const ManagerSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.keys,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<Key>? keys;
  @override
  Widget build(BuildContext context) {
    final t = managerThemeOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: List.generate(
            labels.length,
            (i) => TextButton(
              key: keys?[i],
              style: TextButton.styleFrom(
                backgroundColor: i == selected
                    ? t.surfaceCard
                    : Colors.transparent,
                foregroundColor: i == selected
                    ? t.textPrimary
                    : t.textSecondary,
                minimumSize: const Size(44, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => onSelect(i),
              child: Text(
                labels[i],
                style: managerDesignText(
                  context,
                  12,
                  muted: i != selected,
                  weight: i == selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ManagerKeyValue extends StatelessWidget {
  const ManagerKeyValue(
    this.label,
    this.value, {
    super.key,
    this.emphasis = false,
  });
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: managerDesignText(context, 13, muted: true),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: managerDesignText(
              context,
              emphasis ? 19 : 13,
              weight: emphasis ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class ManagerDetailLink extends StatelessWidget {
  const ManagerDetailLink(
    this.title, {
    super.key,
    this.subtitle,
    required this.onTap,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: managerDesignText(context, 13, weight: FontWeight.w500),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: managerDesignText(context, 11, muted: true)),
    trailing: Icon(
      Icons.chevron_right,
      size: 18,
      color: managerThemeOf(context).textSecondary,
    ),
    onTap: onTap,
  );
}

class ManagerHelpCallout extends StatelessWidget {
  const ManagerHelpCallout(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: managerThemeOf(context).scaffoldBackground,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lightbulb_outline,
          size: 19,
          color: managerThemeOf(context).textSecondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: managerDesignText(context, 12, muted: true)),
        ),
      ],
    ),
  );
}

class ManagerFieldPair extends StatelessWidget {
  const ManagerFieldPair({
    super.key,
    required this.first,
    required this.second,
  });
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        box.maxWidth >= 520 * MediaQuery.textScalerOf(context).scale(1)
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 14), second],
          ),
  );
}

class ManagerDateField extends StatelessWidget {
  const ManagerDateField({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });
  final String label, value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        enabled: onTap != null,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
      ),
      child: Text(value, style: managerDesignText(context, 13)),
    ),
  );
}
