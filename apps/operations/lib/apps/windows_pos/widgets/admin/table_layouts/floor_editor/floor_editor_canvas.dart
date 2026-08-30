import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';
import 'package:flutter/services.dart';

import 'floor_editor_controller.dart';
import 'floor_editor_painter.dart';
import 'floor_editor_viewport.dart';

/// The interactive drawing surface.
///
/// All pointer handling is raw [Listener] work rather than [GestureDetector]:
/// the canvas has to decide on pointer-*down* whether a drag will move,
/// resize, rotate, marquee-select, draw a wall or pan, and gesture-arena
/// disambiguation would add a delay to every one of those.
class FloorEditorCanvas extends StatefulWidget {
  const FloorEditorCanvas({
    super.key,
    required this.controller,
    required this.viewport,
  });

  final FloorEditorController controller;
  final EditorViewportController viewport;

  @override
  State<FloorEditorCanvas> createState() => _FloorEditorCanvasState();
}

enum _PointerMode { none, transform, marquee, segment, pan }

class _FloorEditorCanvasState extends State<FloorEditorCanvas> {
  _PointerMode _mode = _PointerMode.none;
  Offset _lastPanPosition = Offset.zero;
  String? _lastFittedFloorId;

  FloorEditorController get _controller => widget.controller;

  EditorViewportController get _viewport => widget.viewport;

  bool get _additiveModifier {
    final pressed = HardwareKeyboard.instance;
    return pressed.isShiftPressed ||
        pressed.isMetaPressed ||
        pressed.isControlPressed;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // Switching floors reframes the view, otherwise the new floor inherits a
    // pan/zoom that was meaningful only for the old one.
    if (_lastFittedFloorId != null &&
        _lastFittedFloorId != _controller.activeFloorId) {
      _lastFittedFloorId = _controller.activeFloorId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _viewport.fitToCanvas(_controller.floor);
        }
      });
    }
  }

  // ------------------------------------------------------------- pointers

  void _onPointerDown(PointerDownEvent event) {
    final local = event.localPosition;
    final world = _viewport.toWorld(local);
    final isSecondary = event.buttons & kSecondaryMouseButton != 0;
    final isMiddle = event.buttons & kMiddleMouseButton != 0;

    if (_viewport.isPanMode || isMiddle || isSecondary) {
      _mode = _PointerMode.pan;
      _lastPanPosition = local;
      return;
    }

    if (_controller.tool == EditorTool.place) {
      if (_controller.isPlacingSegment) {
        _mode = _PointerMode.segment;
        _controller.beginSegment(world);
      } else {
        _mode = _PointerMode.none;
        _controller.placeAt(world);
      }
      return;
    }

    // Handles win over everything: they sit on top of the object they belong
    // to, and often overlap a neighbour.
    final target = _controller.singleSelection;
    if (target != null) {
      final painter = _painterFor();
      final rotationHandle = painter.rotationHandlePosition(target);
      if ((rotationHandle - local).distance <=
          FloorEditorPainter.handleRadius + 5) {
        _mode = _PointerMode.transform;
        _controller.beginRotate(world);
        return;
      }
      for (final handle in painter.handlePositions(target)) {
        if ((handle.$2 - local).distance <=
            FloorEditorPainter.handleRadius + 4) {
          _mode = _PointerMode.transform;
          _controller.beginResize(handle.$1, world);
          return;
        }
      }
    }

    // A little slop makes thin walls and dividers grabbable.
    final hit = _controller.hitTest(world, tolerance: 6 / _viewport.scale);
    if (hit == null) {
      if (!_additiveModifier) {
        _controller.clearSelection();
      }
      _mode = _PointerMode.marquee;
      _controller.beginMarquee(world);
      return;
    }

    if (_additiveModifier) {
      _controller.toggleSelection(hit.id);
      if (!_controller.isSelected(hit.id)) {
        _mode = _PointerMode.none;
        return;
      }
    } else if (!_controller.isSelected(hit.id)) {
      _controller.selectOnly(hit.id);
    }

    _mode = _PointerMode.transform;
    _controller.beginMove(world);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final local = event.localPosition;
    final world = _viewport.toWorld(local);

    switch (_mode) {
      case _PointerMode.none:
        break;
      case _PointerMode.pan:
        _viewport.panBy(local - _lastPanPosition);
        _lastPanPosition = local;
      case _PointerMode.marquee:
        _controller.updateMarquee(world, additive: _additiveModifier);
      case _PointerMode.segment:
        _controller.updateSegment(world);
      case _PointerMode.transform:
        switch (_controller.gesture) {
          case EditorGesture.move:
            _controller.updateMove(world);
          case EditorGesture.resize:
            _controller.updateResize(world);
          case EditorGesture.rotate:
            _controller.updateRotate(world);
          case EditorGesture.none:
          case EditorGesture.marquee:
          case EditorGesture.drawSegment:
            break;
        }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_mode != _PointerMode.none && _mode != _PointerMode.pan) {
      _controller.endGesture();
    }
    _mode = _PointerMode.none;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _viewport.panBy(Offset(-event.scrollDelta.dy, 0));
        return;
      }
      const wheelStep = 1.1;
      final factor = event.scrollDelta.dy > 0 ? 1 / wheelStep : wheelStep;
      _viewport.zoomBy(factor, event.localPosition);
    } else if (event is PointerScaleEvent) {
      _viewport.zoomBy(event.scale, event.localPosition);
    }
  }

  FloorEditorPainter _painterFor() {
    return FloorEditorPainter(
      floor: _controller.floor,
      scale: _viewport.scale,
      offset: _viewport.offset,
      selection: _controller.selection,
      gridVisible: _controller.gridVisible,
      gridSize: _controller.gridSize,
      guides: _controller.alignmentGuides,
      marquee: _controller.marqueeRect,
      segmentPreview: _controller.segmentPreview,
      segmentThickness: _controller.pendingSpec?.height ?? 16,
      showHandles: _controller.singleSelection != null,
      showSeats: true,
    );
  }

  MouseCursor get _cursor {
    if (_viewport.isPanMode) {
      return SystemMouseCursors.grab;
    }
    if (_controller.tool == EditorTool.place) {
      return SystemMouseCursors.precise;
    }
    return SystemMouseCursors.basic;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _viewport.setViewportSize(size);
          if (_lastFittedFloorId == null && !size.isEmpty) {
            _lastFittedFloorId = _controller.activeFloorId;
            _viewport.fitToCanvas(_controller.floor);
          }
        });

        // The painter captures scale/offset/objects as final fields, so it
        // must be *rebuilt* — not merely repainted — whenever they change.
        // This subtree has no per-object widgets, so a drag frame costs one
        // rebuild plus one repaint no matter how many tables are on the floor.
        return ListenableBuilder(
          listenable: Listenable.merge([_controller, _viewport]),
          builder: (context, _) {
            return ColoredBox(
              color: AdminDesign.surface,
              child: MouseRegion(
                cursor: _cursor,
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: (_) {
                    _controller.cancelGesture();
                    _mode = _PointerMode.none;
                  },
                  onPointerSignal: _onPointerSignal,
                  behavior: HitTestBehavior.opaque,
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _painterFor(),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Floating zoom controls, so pan/zoom is discoverable without knowing the
/// wheel and space-drag shortcuts.
class FloorEditorZoomControls extends StatelessWidget {
  const FloorEditorZoomControls({
    super.key,
    required this.viewport,
    required this.onFit,
  });

  final EditorViewportController viewport;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewport,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: AdminDesign.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminDesign.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomButton(
                icon: Icons.remove,
                tooltip: 'დაპატარავება',
                onPressed: () => viewport.zoomAtCenter(
                  1 / EditorViewportController.zoomStep,
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  '${(viewport.scale * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminDesign.muted,
                  ),
                ),
              ),
              _ZoomButton(
                icon: Icons.add,
                tooltip: 'გადიდება',
                onPressed: () =>
                    viewport.zoomAtCenter(EditorViewportController.zoomStep),
              ),
              Container(
                width: 1,
                height: 18,
                color: AdminDesign.border,
                margin: const EdgeInsets.symmetric(horizontal: 3),
              ),
              _ZoomButton(
                icon: Icons.fit_screen_outlined,
                tooltip: 'მთლიანი ხედი',
                onPressed: onFit,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 17, color: AdminDesign.text),
        ),
      ),
    );
  }
}

/// Small readout that keeps the current mode legible — which tool is armed,
/// how many objects are selected.
class FloorEditorStatusStrip extends StatelessWidget {
  const FloorEditorStatusStrip({super.key, required this.controller});

  final FloorEditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final floor = controller.floor;
        final selected = controller.selection.length;
        final pending = controller.pendingSpec;

        final message = pending != null
            ? (pending.isSegment
                  ? '${pending.label}: დახაზეთ გადათრევით'
                  : '${pending.label}: დააკლიკეთ განსათავსებლად')
            : selected == 0
            ? '${floor.tableCount} მაგიდა · ${floor.seatCount} ადგილი'
            : selected == 1
            ? '1 ობიექტი არჩეულია'
            : '$selected ობიექტი არჩეულია';

        return Container(
          decoration: BoxDecoration(
            color: AdminDesign.panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AdminDesign.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                pending != null
                    ? Icons.add_location_alt_outlined
                    : Icons.info_outline,
                size: 14,
                color: pending != null
                    ? AdminDesign.accentDark
                    : AdminDesign.muted,
              ),
              const SizedBox(width: 7),
              Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: pending != null
                      ? AdminDesign.accentDark
                      : AdminDesign.muted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Nudge distance for arrow keys — one grid step, or a bigger jump with
/// Shift, matching how every layout tool behaves.
double editorNudgeStep(
  FloorEditorController controller, {
  required bool large,
}) {
  final step = controller.snapEnabled ? controller.gridSize : 1.0;
  return large ? math.max(step * 5, 10) : step;
}
