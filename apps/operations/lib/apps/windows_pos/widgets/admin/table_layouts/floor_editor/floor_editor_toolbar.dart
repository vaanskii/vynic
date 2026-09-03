import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/admin_surface.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

import 'floor_editor_controller.dart';

/// Top bar of the editor: navigation back to the floors overview, history,
/// grid/snap toggles, alignment, preview and save.
///
/// At narrow widths the secondary actions collapse into an overflow menu so
/// the canvas keeps the space.
class FloorEditorToolbar extends StatelessWidget {
  const FloorEditorToolbar({
    super.key,
    required this.controller,
    required this.compact,
    required this.isSaving,
    required this.onBack,
    required this.onSave,
    required this.onPreview,
  });

  final FloorEditorController controller;
  final bool compact;
  final bool isSaving;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final multiSelect = controller.selection.length > 1;

        return Container(
          height: 54,
          decoration: const BoxDecoration(
            color: AdminDesign.panel,
            border: Border(bottom: BorderSide(color: AdminDesign.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _ToolbarIcon(
                icon: Icons.arrow_back,
                tooltip: 'სართულებზე დაბრუნება',
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.floor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AdminDesign.text,
                      ),
                    ),
                    if (controller.isDirty)
                      const Text(
                        'შენახვის მოლოდინში',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AdminTones.warningText,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ToolbarDivider(),
              _ToolbarIcon(
                icon: Icons.undo,
                tooltip: 'დაბრუნება (Cmd/Ctrl+Z)',
                onPressed: controller.canUndo ? controller.undo : null,
              ),
              _ToolbarIcon(
                icon: Icons.redo,
                tooltip: 'გამეორება (Cmd/Ctrl+Shift+Z)',
                onPressed: controller.canRedo ? controller.redo : null,
              ),
              if (!compact) ...[
                _ToolbarDivider(),
                _ToolbarToggle(
                  icon: Icons.grid_4x4,
                  label: 'ბადე',
                  value: controller.gridVisible,
                  onChanged: controller.setGridVisible,
                ),
                _ToolbarToggle(
                  icon: Icons.grid_goldenratio,
                  label: 'მიბმა',
                  value: controller.snapEnabled,
                  onChanged: controller.setSnapEnabled,
                ),
              ],
              _ToolbarDivider(),
              if (!compact)
                _AlignmentBar(controller: controller, enabled: multiSelect)
              else
                _OverflowMenu(controller: controller, onPreview: onPreview),
              const Spacer(),
              if (!compact) ...[
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: 17),
                  label: const Text('გადახედვა'),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminDesign.text,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              FilledButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 17),
                label: const Text('შენახვა'),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminDesign.accentDark,
                  foregroundColor: AdminDesign.panel,
                  disabledBackgroundColor: AdminDesign.border,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AlignmentBar extends StatelessWidget {
  const _AlignmentBar({required this.controller, required this.enabled});

  final FloorEditorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final action in <(IconData, String, VoidCallback)>[
          (
            Icons.align_horizontal_left,
            'მარცხნივ სწორება',
            () => controller.align(AlignAxis.left),
          ),
          (
            Icons.align_horizontal_center,
            'ჰორიზონტალური ცენტრი',
            () => controller.align(AlignAxis.centerX),
          ),
          (
            Icons.align_horizontal_right,
            'მარჯვნივ სწორება',
            () => controller.align(AlignAxis.right),
          ),
          (
            Icons.align_vertical_top,
            'ზემოთ სწორება',
            () => controller.align(AlignAxis.top),
          ),
          (
            Icons.align_vertical_center,
            'ვერტიკალური ცენტრი',
            () => controller.align(AlignAxis.centerY),
          ),
          (
            Icons.align_vertical_bottom,
            'ქვემოთ სწორება',
            () => controller.align(AlignAxis.bottom),
          ),
          (
            Icons.horizontal_distribute,
            'ჰორიზონტალურად გადანაწილება',
            () => controller.distribute(horizontal: true),
          ),
          (
            Icons.vertical_distribute,
            'ვერტიკალურად გადანაწილება',
            () => controller.distribute(horizontal: false),
          ),
        ])
          _ToolbarIcon(
            icon: action.$1,
            tooltip: action.$2,
            onPressed: enabled ? action.$3 : null,
          ),
      ],
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.controller, required this.onPreview});

  final FloorEditorController controller;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'დამატებითი მოქმედებები',
      icon: const Icon(Icons.more_horiz, size: 19),
      color: AdminDesign.panel,
      onSelected: (value) {
        switch (value) {
          case 'grid':
            controller.setGridVisible(!controller.gridVisible);
          case 'snap':
            controller.setSnapEnabled(!controller.snapEnabled);
          case 'preview':
            onPreview();
          case 'align-left':
            controller.align(AlignAxis.left);
          case 'align-top':
            controller.align(AlignAxis.top);
          case 'distribute-h':
            controller.distribute(horizontal: true);
          case 'distribute-v':
            controller.distribute(horizontal: false);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'grid',
          checked: controller.gridVisible,
          child: const Text('ბადე'),
        ),
        CheckedPopupMenuItem(
          value: 'snap',
          checked: controller.snapEnabled,
          child: const Text('ბადეზე მიბმა'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'align-left',
          child: Text('მარცხნივ სწორება'),
        ),
        const PopupMenuItem(value: 'align-top', child: Text('ზემოთ სწორება')),
        const PopupMenuItem(
          value: 'distribute-h',
          child: Text('ჰორიზონტალურად გადანაწილება'),
        ),
        const PopupMenuItem(
          value: 'distribute-v',
          child: Text('ვერტიკალურად გადანაწილება'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'preview', child: Text('გადახედვა')),
      ],
    );
  }
}

class _ToolbarIcon extends StatelessWidget {
  const _ToolbarIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: AdminDesign.text,
        disabledColor: VynicFloorTokens.textFaint,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }
}

class _ToolbarToggle extends StatelessWidget {
  const _ToolbarToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label: ${value ? 'ჩართული' : 'გამორთული'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!value),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: value ? AdminDesign.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: value ? AdminDesign.accentDark : AdminDesign.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: value ? AdminDesign.accentDark : AdminDesign.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: value ? AdminDesign.accentDark : AdminDesign.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: AdminDesign.border,
    );
  }
}
