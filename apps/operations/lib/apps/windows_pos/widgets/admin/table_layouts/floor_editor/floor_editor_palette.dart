import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

import 'floor_editor_controller.dart';
import 'floor_editor_presets.dart';

/// Left tool rail: the select tool plus every placeable object.
///
/// Entries that carry presets (a table's seat counts) open a small menu on
/// click; clicking the icon itself arms the group's default preset. Either
/// way the next canvas click places it — no form in between.
class FloorEditorPalette extends StatelessWidget {
  const FloorEditorPalette({
    super.key,
    required this.controller,
    required this.compact,
  });

  final FloorEditorController controller;

  /// Icon-only mode for narrow windows (1024×768 and friends).
  final bool compact;

  double get _width => compact ? 60 : 168;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          width: _width,
          decoration: const BoxDecoration(
            color: AdminDesign.panel,
            border: Border(right: BorderSide(color: AdminDesign.border)),
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _PaletteSectionTitle(title: 'არჩევა', compact: compact),
              _PaletteButton(
                icon: Icons.near_me_outlined,
                label: 'არჩევა / გადატანა',
                tooltip: 'არჩევა და გადატანა (Esc)',
                compact: compact,
                selected: controller.tool == EditorTool.select,
                onTap: () => controller.selectTool(EditorTool.select),
              ),
              for (final group in EditorPresets.groups) ...[
                _PaletteSectionTitle(title: group.title, compact: compact),
                for (final entry in group.entries)
                  _PaletteButton(
                    icon: entry.icon,
                    label: entry.spec.label,
                    tooltip: entry.tooltip,
                    compact: compact,
                    selected:
                        controller.tool == EditorTool.place &&
                        controller.pendingSpec?.id == entry.spec.id,
                    variants: entry.variants,
                    activeVariantId: controller.pendingSpec?.id,
                    onTap: () => controller.armPlacement(entry.spec),
                    onVariantSelected: controller.armPlacement,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PaletteSectionTitle extends StatelessWidget {
  const _PaletteSectionTitle({required this.title, required this.compact});

  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Divider(height: 1, color: AdminDesign.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w800,
          color: VynicFloorTokens.textFaint,
        ),
      ),
    );
  }
}

class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.compact,
    required this.selected,
    required this.onTap,
    this.variants = const [],
    this.activeVariantId,
    this.onVariantSelected,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;
  final List<EditorPlacementSpec> variants;
  final String? activeVariantId;
  final ValueChanged<EditorPlacementSpec>? onVariantSelected;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AdminDesign.accentDark : AdminDesign.text;

    final content = Container(
      margin: EdgeInsets.symmetric(horizontal: compact ? 8 : 8, vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? AdminDesign.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AdminDesign.accentDark : Colors.transparent,
        ),
      ),
      child: compact
          ? Icon(icon, size: 19, color: foreground)
          : Row(
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ),
                if (variants.isNotEmpty)
                  Icon(
                    Icons.expand_more,
                    size: 15,
                    color: VynicFloorTokens.textFaint,
                  ),
              ],
            ),
    );

    final button = Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: variants.isEmpty ? onTap : null,
        child: content,
      ),
    );

    if (variants.isEmpty) {
      return button;
    }

    return PopupMenuButton<EditorPlacementSpec>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      color: AdminDesign.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AdminDesign.border),
      ),
      onSelected: (spec) => onVariantSelected?.call(spec),
      itemBuilder: (context) => [
        for (final variant in variants)
          PopupMenuItem<EditorPlacementSpec>(
            value: variant,
            height: 38,
            child: Row(
              children: [
                Icon(
                  variant.id == activeVariantId
                      ? Icons.check
                      : Icons.chair_alt_outlined,
                  size: 16,
                  color: variant.id == activeVariantId
                      ? AdminDesign.accentDark
                      : AdminDesign.muted,
                ),
                const SizedBox(width: 10),
                Text(
                  variant.label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AdminDesign.text,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: content,
    );
  }
}
