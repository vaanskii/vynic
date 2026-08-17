import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'floor_editor_controller.dart';
import 'floor_editor_model.dart';
import 'floor_editor_presets.dart';

/// Right-hand inspector.
///
/// Secondary by design: everything here can also be done on the canvas. It
/// exists for the values direct manipulation cannot express precisely — a
/// name, a seat count, an exact rotation.
class FloorEditorInspector extends StatefulWidget {
  const FloorEditorInspector({
    super.key,
    required this.controller,
    required this.width,
  });

  final FloorEditorController controller;
  final double width;

  @override
  State<FloorEditorInspector> createState() => _FloorEditorInspectorState();
}

class _FloorEditorInspectorState extends State<FloorEditorInspector> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _capacity = TextEditingController();
  final TextEditingController _floorName = TextEditingController();

  /// Which object the text fields currently mirror. Re-syncing only when
  /// this changes stops a drag from stomping on text the user is typing.
  String? _syncedObjectId;
  String? _syncedFloorId;

  FloorEditorController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFields);
    _syncFields();
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFields);
    _label.dispose();
    _capacity.dispose();
    _floorName.dispose();
    super.dispose();
  }

  void _syncFields() {
    final selected = _controller.singleSelection;
    if (selected?.id != _syncedObjectId) {
      _syncedObjectId = selected?.id;
      _label.text = selected?.label ?? '';
      _capacity.text = (selected?.capacity ?? 0) > 0
          ? '${selected!.capacity}'
          : '';
    }
    if (_controller.activeFloorId != _syncedFloorId) {
      _syncedFloorId = _controller.activeFloorId;
      _floorName.text = _controller.floor.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      decoration: const BoxDecoration(
        color: VynicColors.card,
        border: Border(left: BorderSide(color: VynicColors.border)),
      ),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final selected = _controller.selectedObjects;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
            children: [
              if (selected.isEmpty)
                ..._floorProperties()
              else if (selected.length == 1)
                ..._objectProperties(selected.first)
              else
                ..._multiProperties(selected),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------- floor section

  List<Widget> _floorProperties() {
    final floor = _controller.floor;
    return [
      const _SectionLabel('სართული'),
      _TextRow(
        label: 'დასახელება',
        controller: _floorName,
        onSubmitted: _controller.setFloorName,
      ),
      const SizedBox(height: 14),
      const _SectionLabel('ტილო'),
      Row(
        children: [
          Expanded(
            child: _NumberField(
              label: 'სიგანე',
              value: floor.canvasWidth,
              onChanged: (value) => _controller.setCanvasSize(width: value),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              label: 'სიმაღლე',
              value: floor.canvasHeight,
              onChanged: (value) => _controller.setCanvasSize(height: value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const _SectionLabel('ტილოს ფორმა'),
      _CanvasAspectRow(
        canvasWidth: floor.canvasWidth,
        canvasHeight: floor.canvasHeight,
        onFit: _controller.fitCanvasToAspect,
      ),
      const SizedBox(height: 12),
      _NumberField(
        label: 'ბადის ბიჯი',
        value: _controller.gridSize,
        onChanged: _controller.setGridSize,
      ),
      const SizedBox(height: 16),
      const _SectionLabel('შემაჯამებელი'),
      _StatRow(label: 'მაგიდა', value: '${floor.tableCount}'),
      _StatRow(label: 'ადგილი', value: '${floor.seatCount}'),
      _StatRow(
        label: 'სხვა ობიექტი',
        value: '${floor.objects.length - floor.tableCount}',
      ),
      const SizedBox(height: 18),
      const _HintCard(
        lines: [
          'აირჩიეთ ობიექტი მარცხენა პანელიდან და დააკლიკეთ ტილოზე.',
          'კედელი და ტიხარი იხაზება გადათრევით.',
          'Space + გადათრევა — ტილოს გადაადგილება.',
        ],
      ),
    ];
  }

  // ------------------------------------------------------- object section

  List<Widget> _objectProperties(EditorObject object) {
    final zone = _controller.floor.zoneAt(object.center);
    return [
      _SectionLabel(EditorPresets.typeLabel(object.type).toUpperCase()),
      _TextRow(
        label: object.isTable ? 'მაგიდის სახელი' : 'წარწერა',
        controller: _label,
        onSubmitted: _controller.updateSelectedLabel,
      ),
      if (object.isTable) ...[
        const SizedBox(height: 10),
        _TextRow(
          label: 'ადგილები',
          controller: _capacity,
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (value) =>
              _controller.updateSelectedCapacity(int.tryParse(value) ?? 0),
        ),
        const SizedBox(height: 14),
        const _SectionLabel('ფორმა'),
        _ShapePicker(
          value: object.tableShape,
          onChanged: _controller.updateSelectedShape,
        ),
      ],
      const SizedBox(height: 14),
      _SectionLabel(object.isSegment ? 'სიგრძე და სისქე' : 'ზომა'),
      Row(
        children: [
          Expanded(
            child: _NumberField(
              label: object.isSegment ? 'სიგრძე' : 'სიგანე',
              value: object.width,
              onChanged: (value) =>
                  _controller.updateSelectedSize(width: value),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              label: object.isSegment ? 'სისქე' : 'სიმაღლე',
              value: object.height,
              onChanged: (value) =>
                  _controller.updateSelectedSize(height: value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const _SectionLabel('მობრუნება'),
      _RotationRow(
        value: object.rotation,
        onChanged: _controller.updateSelectedRotation,
        onStep: _controller.rotateSelectionBy,
      ),
      const SizedBox(height: 14),
      const _SectionLabel('არეალი'),
      _StatRow(
        label: 'ზონა',
        value: zone?.label ?? '—',
        // Zone membership is derived from where the object sits, because the
        // legacy table model has no per-table area field yet.
        hint: 'განისაზღვრება მდებარეობით',
      ),
      const SizedBox(height: 18),
      _ActionRow(controller: _controller),
    ];
  }

  List<Widget> _multiProperties(List<EditorObject> selected) {
    final tables = selected.where((object) => object.isTable).toList();
    return [
      _SectionLabel('${selected.length} ობიექტი არჩეულია'),
      const SizedBox(height: 6),
      if (tables.isNotEmpty) ...[
        _StatRow(label: 'მაგიდა', value: '${tables.length}'),
        _StatRow(
          label: 'ჯამური ადგილები',
          value: '${tables.fold(0, (sum, table) => sum + table.capacity)}',
        ),
        const SizedBox(height: 12),
        const _SectionLabel('საერთო ფორმა'),
        _ShapePicker(value: null, onChanged: _controller.updateSelectedShape),
        const SizedBox(height: 14),
      ],
      const _SectionLabel('მობრუნება'),
      Row(
        children: [
          Expanded(
            child: _MiniButton(
              icon: Icons.rotate_left,
              label: '-90°',
              onPressed: () => _controller.rotateSelectionBy(-90),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniButton(
              icon: Icons.rotate_right,
              label: '+90°',
              onPressed: () => _controller.rotateSelectionBy(90),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const _SectionLabel('სწორება'),
      _AlignGrid(controller: _controller),
      const SizedBox(height: 18),
      _ActionRow(controller: _controller),
    ];
  }
}

// ------------------------------------------------------------- components

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w800,
          color: VynicColors.textDisabled,
        ),
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.controller,
    required this.onSubmitted,
    this.keyboardType,
    this.formatters,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: VynicColors.textMuted,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: VynicColors.textPrimary,
          ),
          decoration: _fieldDecoration(),
          onSubmitted: onSubmitted,
          onTapOutside: (_) {
            FocusManager.instance.primaryFocus?.unfocus();
            onSubmitted(controller.text);
          },
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration() {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: VynicColors.cardSoft,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: VynicColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: VynicColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: VynicColors.accent, width: 1.5),
    ),
  );
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value.round()}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only mirror external changes while the field is idle, so dragging a
    // resize handle updates the readout without fighting the caret.
    if (!_focus.hasFocus && widget.value.round() != oldWidget.value.round()) {
      _controller.text = '${widget.value.round()}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value.round()}';
      return;
    }
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: VynicColors.textMuted,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: _controller,
          focusNode: _focus,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: VynicColors.textPrimary,
          ),
          decoration: _fieldDecoration(),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) {
            if (_focus.hasFocus) {
              _focus.unfocus();
              _commit();
            }
          },
        ),
      ],
    );
  }
}

class _RotationRow extends StatelessWidget {
  const _RotationRow({
    required this.value,
    required this.onChanged,
    required this.onStep,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onStep;

  @override
  Widget build(BuildContext context) {
    // _MiniButton lays its label out with a Flexible, so every instance needs
    // a bounded width — either an Expanded parent or an explicit box here.
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: _MiniButton(
            icon: Icons.rotate_left,
            label: '-45°',
            onPressed: () => onStep(-45),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VynicColors.cardSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VynicColors.border),
            ),
            child: Text(
              '${value.round()}°',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: VynicColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 62,
          child: _MiniButton(
            icon: Icons.rotate_right,
            label: '+45°',
            onPressed: () => onStep(45),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'გასწორება (0°)',
          child: SizedBox(
            width: 40,
            child: _MiniButton(
              icon: Icons.straighten,
              label: null,
              onPressed: () => onChanged(0),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShapePicker extends StatelessWidget {
  const _ShapePicker({required this.value, required this.onChanged});

  final RestaurantTableShape? value;
  final ValueChanged<RestaurantTableShape> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final shape in EditorPresets.tableShapes)
          Tooltip(
            message: shape.$2,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(shape.$1),
              child: Container(
                width: 40,
                height: 36,
                decoration: BoxDecoration(
                  color: value == shape.$1
                      ? VynicColors.accentSoft
                      : VynicColors.cardSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: value == shape.$1
                        ? VynicColors.accent
                        : VynicColors.border,
                  ),
                ),
                child: Icon(
                  shape.$3,
                  size: 17,
                  color: value == shape.$1
                      ? VynicColors.accent
                      : VynicColors.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AlignGrid extends StatelessWidget {
  const _AlignGrid({required this.controller});

  final FloorEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final action in <(IconData, String, VoidCallback)>[
          (
            Icons.align_horizontal_left,
            'მარცხნივ',
            () => controller.align(AlignAxis.left),
          ),
          (
            Icons.align_horizontal_center,
            'ცენტრი',
            () => controller.align(AlignAxis.centerX),
          ),
          (
            Icons.align_horizontal_right,
            'მარჯვნივ',
            () => controller.align(AlignAxis.right),
          ),
          (
            Icons.align_vertical_top,
            'ზემოთ',
            () => controller.align(AlignAxis.top),
          ),
          (
            Icons.align_vertical_center,
            'შუა',
            () => controller.align(AlignAxis.centerY),
          ),
          (
            Icons.align_vertical_bottom,
            'ქვემოთ',
            () => controller.align(AlignAxis.bottom),
          ),
          (
            Icons.horizontal_distribute,
            'ჰორიზონტალურად',
            () => controller.distribute(horizontal: true),
          ),
          (
            Icons.vertical_distribute,
            'ვერტიკალურად',
            () => controller.distribute(horizontal: false),
          ),
        ])
          Tooltip(
            message: action.$2,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: action.$3,
              child: Container(
                width: 40,
                height: 36,
                decoration: BoxDecoration(
                  color: VynicColors.cardSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VynicColors.border),
                ),
                child: Icon(action.$1, size: 17, color: VynicColors.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.controller});

  final FloorEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniButton(
            icon: Icons.copy_all_outlined,
            label: 'დუბლირება',
            onPressed: controller.duplicateSelection,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniButton(
            icon: Icons.delete_outline,
            label: 'წაშლა',
            danger: true,
            onPressed: controller.deleteSelection,
          ),
        ),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? VynicColors.danger : VynicColors.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: danger ? VynicColors.dangerSoft : VynicColors.cardSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: danger ? VynicColors.dangerBorder : VynicColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            if (label != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: VynicColors.textMuted,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: VynicColors.textPrimary,
                ),
              ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: VynicColors.textDisabled,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VynicColors.cardSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VynicColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: VynicColors.textDisabled,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: VynicColors.textMuted,
                      ),
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

/// Canvas shape presets.
///
/// The POS fits a floor with `min(scaleX, scaleY)` so proportions survive,
/// which means a canvas shaped differently from the plan panel is letterboxed
/// — the spare width becomes dead margin on the left and right of the
/// operational screen. The built-in floors are 1005x1101 and 953x958, both
/// carried over from the old SVG maps, so out of the box roughly a third of the
/// width is wasted on a landscape terminal. These presets fix that by growing
/// the canvas to a landscape shape; growing (never shrinking) means no table
/// can be left outside.
class _CanvasAspectRow extends StatelessWidget {
  const _CanvasAspectRow({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.onFit,
  });

  final double canvasWidth;
  final double canvasHeight;
  final ValueChanged<double> onFit;

  /// The shape most POS terminals actually have; used for the readout.
  static const double _referenceAspect = 16 / 10;

  static const List<(String, double)> _presets = [
    ('16:10', 16 / 10),
    ('16:9', 16 / 9),
    ('4:3', 4 / 3),
  ];

  @override
  Widget build(BuildContext context) {
    final aspect = canvasHeight <= 0 ? 0.0 : canvasWidth / canvasHeight;
    // How much of the panel's width the plan will actually cover.
    final usedFraction = aspect <= 0
        ? 0.0
        : (aspect / _referenceAspect).clamp(0.0, 1.0);
    final wastedPercent = ((1 - usedFraction) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in _presets)
              Tooltip(
                message: 'ტილო ${preset.$1} პროპორციაზე',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onFit(preset.$2),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (aspect - preset.$2).abs() < 0.01
                          ? VynicColors.accentSoft
                          : VynicColors.cardSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (aspect - preset.$2).abs() < 0.01
                            ? VynicColors.accent
                            : VynicColors.border,
                      ),
                    ),
                    child: Text(
                      preset.$1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (aspect - preset.$2).abs() < 0.01
                            ? VynicColors.accent
                            : VynicColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          wastedPercent <= 1
              ? 'POS-ის სიგანე სრულად გამოიყენება.'
              : 'POS 16:10 ეკრანზე იკარგება სიგანის ~$wastedPercent% '
                    '(ცარიელი მინდვრები გვერდებზე).',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: wastedPercent <= 1
                ? VynicColors.successText
                : VynicColors.warningText,
          ),
        ),
      ],
    );
  }
}
