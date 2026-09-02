import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:vynic/apps/windows_pos/widgets/shared/pos_surface.dart';
import 'package:vynic/core/models/receipt_header_layout.dart';
import 'package:vynic/core/services/pos/backup_file_picker.dart';
import 'package:vynic/core/services/pos/venue_identity_draft.dart';
import 'package:vynic/core/services/pos/venue_logo_service.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_language.dart';
import 'package:vynic/core/widgets/pos_keyboard/pos_keyboard_sheet.dart';

/// Who this venue is, as it appears at the top of every check.
///
/// Shared between first-run setup and the admin panel on purpose: it is the
/// same facts, and finding a different-looking form when you want to change
/// the phone number is how people end up with two half-filled records.
///
/// Nothing here writes to the database. Edits go into the [VenueIdentityDraft]
/// the host owns, and land when it is saved — so an operator trying
/// arrangements is not changing what customers are handed while they do it.
class VenueIdentityPanel extends StatefulWidget {
  const VenueIdentityPanel({
    super.key,
    required this.draft,
    this.showAddressAndPhone = true,
    this.showSaveButton = true,
  });

  final VenueIdentityDraft draft;

  /// First-run setup asks only for the name and the logo; the rest can wait
  /// until someone is sitting down with the paperwork.
  final bool showAddressAndPhone;

  /// Setup drives saving from its own „start" button, so it hides this one
  /// rather than asking a first-time user to press two.
  final bool showSaveButton;

  @override
  State<VenueIdentityPanel> createState() => _VenueIdentityPanelState();
}

class _VenueIdentityPanelState extends State<VenueIdentityPanel> {
  bool _busy = false;
  int _threshold = VenueLogoService.defaultThreshold;

  VenueIdentityDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraftChanged);
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _editText({
    required String title,
    required String current,
    required void Function(String value) apply,
  }) async {
    final controller = TextEditingController(text: current);
    try {
      final entered = await showPosKeyboardInputSheet(
        context: context,
        controller: controller,
        title: title,
        initialLanguage: PosKeyboardLanguage.georgian,
      );
      if (entered == null || !mounted) return;
      apply(entered.trim());
    } finally {
      controller.dispose();
    }
  }

  Future<void> _pickLogo() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await BackupFilePicker.pickImageFile();
      if (path == null || !mounted) return;

      final source = await File(path).readAsBytes();
      final result = VenueLogoService.fromBytes(source, threshold: _threshold);
      if (!mounted) return;

      if (!result.ok) {
        unawaited(
          showPosToast(
            context: context,
            message: _logoError(result.error),
            style: PosToastStyle.error,
          ),
        );
        return;
      }

      _draft.setLogo(result.png, source: source);
      if (result.isVeryHeavy && mounted) {
        unawaited(
          showPosToast(
            context: context,
            message: 'ლოგო თითქმის მთლიანად შავია — ჩეკზე ლაქად დაიბეჭდება',
            style: PosToastStyle.info,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retrace(int threshold) {
    final source = _draft.sourceImage;
    if (source == null) return;
    final result = VenueLogoService.fromBytes(source, threshold: threshold);
    if (!result.ok) return;
    _draft.setLogo(result.png, source: source);
  }

  /// Writes the stored mark out to a file the operator picks.
  ///
  /// Exports what is *saved*, not the draft: exporting an unsaved experiment
  /// would hand them a file that does not match what the printer has.
  Future<void> _exportLogo() async {
    final logo = _draft.logo;
    if (logo == null || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await BackupFilePicker.pickSaveImageFile(
        suggestedName: 'vynic-logo.png',
      );
      if (path == null || !mounted) return;

      final target = path.toLowerCase().endsWith('.png') ? path : '$path.png';
      await File(target).writeAsBytes(logo, flush: true);
      if (!mounted) return;
      unawaited(showSuccessToast(context, 'ლოგო შენახულია ფაილში'));
    } catch (error) {
      if (!mounted) return;
      unawaited(
        showPosToast(
          context: context,
          message: 'ფაილის ჩაწერა ვერ მოხერხდა',
          style: PosToastStyle.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_draft.isDirty) return;
    setState(() => _busy = true);
    try {
      await _draft.save();
      if (!mounted) return;
      unawaited(showSuccessToast(context, 'შენახულია'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _logoError(String? error) {
    switch (error) {
      case VenueLogoService.tooLarge:
        return 'ფაილი ძალიან დიდია';
      case VenueLogoService.notAnImage:
        return 'ეს ფაილი სურათი არ არის';
      default:
        return 'ფაილი ვერ წაიკითხა';
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = _draft.layout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _VenueField(
          label: 'რესტორნის სახელი',
          value: _draft.name,
          hint: 'ჩეკის თავში დაიბეჭდება',
          onTap: () => _editText(
            title: 'რესტორნის სახელი',
            current: _draft.name,
            apply: (value) => _draft.name = value,
          ),
        ),
        if (widget.showAddressAndPhone) ...[
          const SizedBox(height: 10),
          _VenueField(
            label: 'მისამართი',
            value: _draft.address,
            hint: 'არასავალდებულო',
            onTap: () => _editText(
              title: 'მისამართი',
              current: _draft.address,
              apply: (value) => _draft.address = value,
            ),
          ),
          const SizedBox(height: 10),
          _VenueField(
            label: 'ტელეფონი',
            value: _draft.phone,
            hint: 'არასავალდებულო',
            onTap: () => _editText(
              title: 'ტელეფონი',
              current: _draft.phone,
              apply: (value) => _draft.phone = value,
            ),
          ),
          const SizedBox(height: 10),
          _VenueField(
            label: 'საიდენტიფიკაციო კოდი',
            value: _draft.legalId,
            hint: 'ფინანსურ ანგარიშებში დაიბეჭდება',
            onTap: () => _editText(
              title: 'საიდენტიფიკაციო კოდი',
              current: _draft.legalId,
              apply: (value) => _draft.legalId = value,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const PosSectionLabel('ჩეკის ლოგო'),
        const SizedBox(height: 8),
        _LogoTile(
          logo: _draft.logo,
          busy: _busy,
          onPick: _pickLogo,
          onRemove: _draft.logo == null ? null : () => _draft.setLogo(null),
          onExport: _draft.logo == null ? null : _exportLogo,
        ),
        if (_draft.logo != null) ...[
          const SizedBox(height: 10),
          _ScaleSlider(
            value: layout.clampedScale,
            logo: _draft.logo,
            onChanged: (value) =>
                _draft.layout = layout.copyWith(logoScale: value),
          ),
        ],
        if (_draft.sourceImage != null) ...[
          const SizedBox(height: 10),
          _ThresholdSlider(
            value: _threshold,
            onChanged: (value) => setState(() => _threshold = value),
            onSettled: _retrace,
          ),
        ],
        if (widget.showAddressAndPhone) ...[
          const SizedBox(height: 18),
          const PosSectionLabel('განლაგება ჩეკზე'),
          const SizedBox(height: 8),
          _AlignRow(
            label: 'ლოგო',
            value: layout.logoAlign,
            onChanged: (align) =>
                _draft.layout = layout.copyWith(logoAlign: align),
          ),
          const SizedBox(height: 8),
          _AlignRow(
            label: 'სახელი და კონტაქტი',
            value: layout.textAlign,
            onChanged: (align) =>
                _draft.layout = layout.copyWith(textAlign: align),
          ),
          const SizedBox(height: 8),
          _OrderRow(
            logoFirst: layout.logoFirst,
            onChanged: (first) =>
                _draft.layout = layout.copyWith(logoFirst: first),
          ),
        ],
        const SizedBox(height: 14),
        _HeaderPreview(
          logo: _draft.logo,
          layout: layout,
          name: _draft.name,
          address: widget.showAddressAndPhone ? _draft.address : '',
          phone: widget.showAddressAndPhone ? _draft.phone : '',
        ),
        if (widget.showSaveButton) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              if (_draft.isDirty) ...[
                PosActionButton(
                  label: 'დაბრუნება',
                  icon: Icons.undo,
                  onTap: _busy ? null : _draft.revert,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: PosPrimaryButton(
                  label: _draft.isDirty ? 'შენახვა' : 'შენახულია',
                  icon: _draft.isDirty ? Icons.save_outlined : Icons.check,
                  height: 48,
                  onTap: _draft.isDirty && !_busy ? _save : null,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// [VenueIdentityPanel] with a draft of its own.
///
/// For hosts that are stateless — the admin settings section is one long
/// `StatelessWidget` — and have nowhere to keep one.
class VenueIdentityCard extends StatefulWidget {
  const VenueIdentityCard({super.key});

  @override
  State<VenueIdentityCard> createState() => _VenueIdentityCardState();
}

class _VenueIdentityCardState extends State<VenueIdentityCard> {
  final VenueIdentityDraft _draft = VenueIdentityDraft();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VenueIdentityPanel(draft: _draft);
}

/// One labelled line of venue detail. Read-only and keyboard-driven, like
/// every other text input on a terminal with no hardware keyboard.
class _VenueField extends StatelessWidget {
  const _VenueField({
    required this.label,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  final String label;
  final String value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return Material(
      color: VynicFloorTokens.page,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: VynicFloorTokens.panelBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: VynicFloorTokens.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      empty ? hint : value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: empty
                            ? VynicFloorTokens.textFaint
                            : VynicFloorTokens.text,
                        fontSize: 15.5,
                        fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.keyboard_alt_outlined,
                size: 18,
                color: VynicFloorTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The logo, as it will actually print.
///
/// Shown on white at its stored size, because that is the whole point of
/// converting on upload rather than at print time: what is in this box is what
/// comes out of the printer.
class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.logo,
    required this.busy,
    required this.onPick,
    required this.onRemove,
    required this.onExport,
  });

  final Uint8List? logo;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  /// Writes the mark out to a file. Once the source is gone, the database is
  /// the only copy there is.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VynicFloorTokens.page,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // White, not the page tint: a receipt is white paper, and a
              // preview on anything else lies about how the mark will look.
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: VynicFloorTokens.panelBorder),
            ),
            child: logo == null
                ? const Text(
                    'ლოგო არ არის — ჩეკზე მხოლოდ სახელი დაიბეჭდება',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: VynicFloorTokens.textFaint,
                      fontSize: 12.5,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(
                      logo!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PosActionButton(
                  label: busy
                      ? 'იტვირთება…'
                      : (logo == null ? 'ლოგოს ატვირთვა' : 'შეცვლა'),
                  icon: Icons.image_outlined,
                  expand: true,
                  onTap: busy ? null : onPick,
                ),
              ),
              if (onExport != null) ...[
                const SizedBox(width: 8),
                PosActionButton(
                  label: 'ექსპორტი',
                  icon: Icons.download_outlined,
                  onTap: busy ? null : onExport,
                ),
              ],
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                PosActionButton(
                  label: 'წაშლა',
                  icon: Icons.delete_outline,
                  tone: PosActionTone.danger,
                  onTap: busy ? null : onRemove,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// How much of an uploaded image survives as ink.
///
/// The tracing threshold, in plain terms: drag left and only the darkest parts
/// of the mark print, drag right and mid-tones join them. A flat wordmark wants
/// the left; a shaded crest needs the right. Re-traced from the file the
/// operator picked, not from the already-traced result — tracing twice does
/// nothing.
class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.value,
    required this.onChanged,
    required this.onSettled,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onSettled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: BoxDecoration(
        color: VynicFloorTokens.page,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'მელნის რაოდენობა',
                  style: TextStyle(
                    color: VynicFloorTokens.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  color: VynicFloorTokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: VynicFloorTokens.accentStrong,
              inactiveTrackColor: VynicFloorTokens.badgeFill,
              thumbColor: VynicFloorTokens.accentStrong,
              overlayColor: VynicFloorTokens.accentSoft,
              trackHeight: 4,
            ),
            child: Slider(
              value: value.toDouble(),
              min: 40,
              max: 220,
              divisions: 18,
              onChanged: (raw) => onChanged(raw.round()),
              // Re-traced on release, not on every frame: each pass decodes
              // and re-encodes the whole image.
              onChangeEnd: (raw) => onSettled(raw.round()),
            ),
          ),
        ],
      ),
    );
  }
}

/// How big the logo prints.
///
/// A fraction of the box the renderer fits the mark into, so „half" means half
/// the size on paper rather than half of some canvas nobody sees. Applied
/// live: it is only arithmetic, and the preview above moves with it.
class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.value,
    required this.onChanged,
    required this.logo,
  });

  final double value;
  final ValueChanged<double> onChanged;

  /// Needed to say how wide the mark will actually be. A percentage on its own
  /// is a fraction of a box nobody can see — which is exactly how „100%" came
  /// to mean „21% of the paper".
  final Uint8List? logo;

  /// „100%  ·  70 მმ" — the fraction and the fact.
  String get _sizeLabel {
    final percent = '${(value * 100).round()}%';
    final bytes = logo;
    if (bytes == null) return percent;
    final size = VenueLogoService.pngSize(bytes);
    if (size == null) return percent;
    final drawn = receiptLogoSize(
      sourceWidth: size.width.toDouble(),
      sourceHeight: size.height.toDouble(),
      scale: value,
    );
    // 576 dots across roughly 72mm of printable width on an 80mm roll.
    final mm = (drawn.width / receiptPaperWidth * 72).round();
    return '$percent  ·  $mm მმ';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      decoration: BoxDecoration(
        color: VynicFloorTokens.page,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: VynicFloorTokens.panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ლოგოს ზომა',
                  style: TextStyle(
                    color: VynicFloorTokens.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _sizeLabel,
                style: const TextStyle(
                  color: VynicFloorTokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: VynicFloorTokens.accentStrong,
              inactiveTrackColor: VynicFloorTokens.badgeFill,
              thumbColor: VynicFloorTokens.accentStrong,
              overlayColor: VynicFloorTokens.accentSoft,
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(
                ReceiptHeaderLayout.minScale,
                ReceiptHeaderLayout.maxScale,
              ),
              min: ReceiptHeaderLayout.minScale,
              max: ReceiptHeaderLayout.maxScale,
              divisions: 14,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Left / centre / right, for one element of the header.
class _AlignRow extends StatelessWidget {
  const _AlignRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final ReceiptAlign value;
  final ValueChanged<ReceiptAlign> onChanged;

  static const _icons = {
    ReceiptAlign.left: Icons.format_align_left,
    ReceiptAlign.center: Icons.format_align_center,
    ReceiptAlign.right: Icons.format_align_right,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: VynicFloorTokens.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final option in ReceiptAlign.values) ...[
          const SizedBox(width: 6),
          _AlignButton(
            icon: _icons[option]!,
            tooltip: option.label,
            selected: option == value,
            onTap: () => onChanged(option),
          ),
        ],
      ],
    );
  }
}

class _AlignButton extends StatelessWidget {
  const _AlignButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? VynicFloorTokens.accentSoft : VynicFloorTokens.panel,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            width: 40,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? const Color(0xFFE2DCF2)
                    : VynicFloorTokens.panelBorder,
              ),
            ),
            child: Icon(
              icon,
              size: 17,
              color: selected
                  ? VynicFloorTokens.accentText
                  : VynicFloorTokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Which of the two comes first down the paper.
class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.logoFirst, required this.onChanged});

  final bool logoFirst;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Flexible(
          child: Text(
            'რიგითობა',
            style: TextStyle(
              color: VynicFloorTokens.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // A bounded width on purpose: `PosPaneSwitch` divides its space with
        // `Expanded`, and a Row hands a non-flex child unbounded width — which
        // is exactly the pair Flutter refuses to lay out.
        SizedBox(
          width: 260,
          child: PosPaneSwitch(
            labels: const ['ლოგო ზემოთ', 'სახელი ზემოთ'],
            selectedIndex: logoFirst ? 0 : 1,
            onSelected: (index) => onChanged(index == 0),
          ),
        ),
      ],
    );
  }
}

/// The top of the check, arranged the way it will print.
///
/// Not a rendered receipt — a scaled sketch of the header, on white, so the
/// effect of moving something is visible without spooling a print job. The
/// real receipt is the same two blocks in the same order.
class _HeaderPreview extends StatelessWidget {
  const _HeaderPreview({
    required this.logo,
    required this.layout,
    required this.name,
    required this.address,
    required this.phone,
  });

  final Uint8List? logo;
  final ReceiptHeaderLayout layout;

  /// From the draft, not the database — the whole point of the preview is to
  /// show what is about to be saved.
  final String name;
  final String address;
  final String phone;

  /// The preview's stand-in for the roll's printable width. Everything inside
  /// is divided down from printer dots by the same factor.
  static const double _paperWidth = 288;

  CrossAxisAlignment _cross(ReceiptAlign align) => switch (align) {
    ReceiptAlign.left => CrossAxisAlignment.start,
    ReceiptAlign.center => CrossAxisAlignment.center,
    ReceiptAlign.right => CrossAxisAlignment.end,
  };

  TextAlign _text(ReceiptAlign align) => switch (align) {
    ReceiptAlign.left => TextAlign.left,
    ReceiptAlign.center => TextAlign.center,
    ReceiptAlign.right => TextAlign.right,
  };

  @override
  Widget build(BuildContext context) {
    // The preview is the paper, to scale. Its width stands for the receipt's
    // printable width, so the mark is drawn through the same
    // `receiptLogoSize` the printer uses and then divided down — a preview
    // that computes its own size is a preview that can agree with the slider
    // and disagree with the printer.
    final source = logo == null ? null : VenueLogoService.pngSize(logo!);
    final drawn = source == null
        ? Size.zero
        : receiptLogoSize(
            sourceWidth: source.width.toDouble(),
            sourceHeight: source.height.toDouble(),
            scale: layout.clampedScale,
          );
    final previewFactor = _paperWidth / receiptPaperWidth;

    final logoBlock = logo == null || drawn.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: switch (layout.logoAlign) {
                ReceiptAlign.left => Alignment.centerLeft,
                ReceiptAlign.center => Alignment.center,
                ReceiptAlign.right => Alignment.centerRight,
              },
              child: Image.memory(
                logo!,
                width: drawn.width * previewFactor,
                height: drawn.height * previewFactor,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
              ),
            ),
          );

    final textBlock = Column(
      crossAxisAlignment: _cross(layout.textAlign),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.isNotEmpty)
          Text(
            name,
            textAlign: _text(layout.textAlign),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (address.isNotEmpty)
          Text(
            address,
            textAlign: _text(layout.textAlign),
            style: const TextStyle(color: Colors.black87, fontSize: 10),
          ),
        if (phone.isNotEmpty)
          Text(
            phone,
            textAlign: _text(layout.textAlign),
            style: const TextStyle(color: Colors.black87, fontSize: 10),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PosSectionLabel('ასე დაიბეჭდება'),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: _paperWidth,
            // The same side margin the printer keeps, divided down: left- and
            // right-aligned content sits where it will actually sit.
            padding: EdgeInsets.fromLTRB(
              receiptSideMargin * previewFactor,
              14,
              receiptSideMargin * previewFactor,
              12,
            ),
            decoration: BoxDecoration(
              // White: it is paper.
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: VynicFloorTokens.panelBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (layout.logoFirst) ...[
                  logoBlock,
                  textBlock,
                ] else ...[
                  textBlock,
                  const SizedBox(height: 8),
                  logoBlock,
                ],
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFDDDDDD)),
                const SizedBox(height: 8),
                const Text(
                  '1x  ხინკალი            25.00',
                  style: TextStyle(color: Colors.black54, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
