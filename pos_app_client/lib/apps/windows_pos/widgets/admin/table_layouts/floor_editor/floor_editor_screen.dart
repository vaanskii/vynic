import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/services/database_service.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/utils/pos_feedback.dart';
import 'floor_editor_canvas.dart';
import 'floor_editor_controller.dart';
import 'floor_editor_inspector.dart';
import 'floor_editor_palette.dart';
import 'floor_editor_preview.dart';
import 'floor_editor_toolbar.dart';
import 'floor_editor_viewport.dart';

/// Dedicated full-workspace floor designer.
///
/// Pushed as its own route rather than living inside a Settings card, so the
/// canvas gets essentially the whole window — the canvas is the primary
/// surface here, and the panels are support.
class FloorEditorScreen extends StatefulWidget {
  const FloorEditorScreen({
    super.key,
    required this.layout,
    required this.floorId,
  });

  final RestaurantTableLayout layout;
  final String floorId;

  /// Returns true when the layout was saved, so the caller can refresh.
  static Future<bool> open(
    BuildContext context, {
    required RestaurantTableLayout layout,
    required String floorId,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            FloorEditorScreen(layout: layout, floorId: floorId),
      ),
    );
    return saved ?? false;
  }

  @override
  State<FloorEditorScreen> createState() => _FloorEditorScreenState();
}

class _FloorEditorScreenState extends State<FloorEditorScreen> {
  late final FloorEditorController _controller;
  final EditorViewportController _viewport = EditorViewportController();
  final FocusNode _canvasFocus = FocusNode(debugLabel: 'floor-editor-canvas');

  bool _isSaving = false;
  bool _savedAtLeastOnce = false;
  bool _inspectorVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = FloorEditorController(
      layout: widget.layout,
      initialFloorId: widget.floorId,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _viewport.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------- persistence

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await DatabaseService.saveActiveRestaurantTableLayout(
        _controller.toLayout(),
      );
      _controller.markSaved();
      _savedAtLeastOnce = true;
      if (!mounted) return;
      unawaited(
        showPosToast(
          context: context,
          message: 'განლაგება შენახულია',
          style: PosToastStyle.success,
        ),
      );
    } on StateError catch (error) {
      // The repository refuses any layout that would strand a live table.
      if (!mounted) return;
      unawaited(
        showPosToast(
          context: context,
          message: 'ვერ შეინახა: ${error.message}',
          style: PosToastStyle.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_controller.isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VynicColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'შენახვის გარეშე გასვლა?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: VynicColors.textPrimary,
          ),
        ),
        content: const Text(
          'განლაგებაში შეტანილი ცვლილებები დაიკარგება.',
          style: TextStyle(fontSize: 13, color: VynicColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('დაბრუნება'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: VynicColors.danger),
            child: const Text('ცვლილებების გაუქმება'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // -------------------------------------------------------------- keyboard

  /// Shortcuts are bound to the canvas focus node, not the app: they only
  /// fire while the canvas itself holds focus, so typing in the inspector is
  /// never hijacked.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _viewport.spaceHeld = false;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;

    if (command) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? _controller.redo() : _controller.undo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _controller.redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD) {
        _controller.duplicateSelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _controller.selectAll();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        unawaited(_save());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.space) {
      _viewport.spaceHeld = true;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _controller.deleteSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _controller
        ..cancelPlacement()
        ..clearSelection();
      return KeyEventResult.handled;
    }

    final step = editorNudgeStep(_controller, large: shift);
    if (key == LogicalKeyboardKey.arrowLeft) {
      _controller.nudgeSelection(-step, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _controller.nudgeSelection(step, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _controller.nudgeSelection(0, -step);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _controller.nudgeSelection(0, step);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // 1024×768 is the smallest supported POS resolution: the panels shrink
    // so the canvas always stays the biggest region.
    final compact = width < 1180;
    final inspectorWidth = width < 1180 ? 236.0 : 284.0;
    final canRoomForInspector = width >= 900;
    final showInspector = _inspectorVisible && canRoomForInspector;

    return PopScope(
      canPop: !_controller.isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: VynicColors.background,
        body: SafeArea(
          child: Column(
            children: [
              FloorEditorToolbar(
                controller: _controller,
                compact: compact,
                isSaving: _isSaving,
                onBack: _handleBack,
                onSave: _save,
                onPreview: () =>
                    FloorEditorPreviewDialog.show(context, _controller.floor),
              ),
              Expanded(
                child: Row(
                  children: [
                    FloorEditorPalette(
                      controller: _controller,
                      compact: compact,
                    ),
                    Expanded(child: _buildWorkspace()),
                    if (showInspector)
                      FloorEditorInspector(
                        controller: _controller,
                        width: inspectorWidth,
                      ),
                    if (canRoomForInspector)
                      _InspectorHandle(
                        expanded: _inspectorVisible,
                        onToggle: () => setState(
                          () => _inspectorVisible = !_inspectorVisible,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    final discard = await _confirmDiscard();
    if (!discard || !mounted) return;
    Navigator.of(context).pop(_savedAtLeastOnce);
  }

  Widget _buildWorkspace() {
    return Focus(
      focusNode: _canvasFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Listener(
        // Any click on the canvas hands focus back, so shortcuts resume
        // working after the inspector has been used.
        onPointerDown: (_) => _canvasFocus.requestFocus(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned.fill(
              child: FloorEditorCanvas(
                controller: _controller,
                viewport: _viewport,
              ),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              child: FloorEditorStatusStrip(controller: _controller),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: FloorEditorZoomControls(
                viewport: _viewport,
                onFit: () => _viewport.fitToCanvas(_controller.floor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin vertical strip that collapses the inspector when the window is tight.
class _InspectorHandle extends StatelessWidget {
  const _InspectorHandle({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? 'პანელის დამალვა' : 'პანელის ჩვენება',
      child: InkWell(
        onTap: onToggle,
        child: Container(
          width: 18,
          decoration: const BoxDecoration(
            color: VynicColors.card,
            border: Border(left: BorderSide(color: VynicColors.border)),
          ),
          alignment: Alignment.center,
          child: Icon(
            expanded ? Icons.chevron_right : Icons.chevron_left,
            size: 15,
            color: VynicColors.textMuted,
          ),
        ),
      ),
    );
  }
}
