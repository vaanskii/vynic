import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'floor_editor_model.dart';

/// Pan/zoom of the editor canvas.
///
/// Deliberately a separate notifier from `FloorEditorController`: panning
/// must repaint the canvas without rebuilding the inspector or toolbar.
///
/// This is the canvas viewport only. It has nothing to do with
/// Settings → UI scaling, which scales the whole application shell.
class EditorViewportController extends ChangeNotifier {
  static const double minScale = 0.2;
  static const double maxScale = 3.0;

  /// One click of the +/- buttons. Zoom out uses its exact reciprocal, so
  /// "in then out" lands back on the scale you started from.
  static const double zoomStep = 1.2;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _viewportSize = Size.zero;
  bool _spaceHeld = false;

  double get scale => _scale;

  Offset get offset => _offset;

  Size get viewportSize => _viewportSize;

  /// True while the pan modifier is held, so the canvas swaps its cursor and
  /// treats drags as panning instead of selection.
  bool get isPanMode => _spaceHeld;

  set spaceHeld(bool value) {
    if (_spaceHeld == value) return;
    _spaceHeld = value;
    notifyListeners();
  }

  Offset toScreen(Offset world) => world * _scale + _offset;

  Offset toWorld(Offset screen) => (screen - _offset) / _scale;

  void setViewportSize(Size size) {
    if (_viewportSize == size) return;
    final wasEmpty = _viewportSize.isEmpty;
    _viewportSize = size;
    if (wasEmpty) {
      // First layout: nothing has been framed yet, so defer to fitToContent.
      return;
    }
    notifyListeners();
  }

  void panBy(Offset delta) {
    _offset += delta;
    notifyListeners();
  }

  /// Zooms around [focalScreen] so the point under the cursor stays put.
  void zoomBy(double factor, Offset focalScreen) {
    final next = (_scale * factor).clamp(minScale, maxScale).toDouble();
    if (next == _scale) return;
    final worldFocal = toWorld(focalScreen);
    _scale = next;
    _offset = focalScreen - worldFocal * _scale;
    notifyListeners();
  }

  void zoomAtCenter(double factor) {
    if (_viewportSize.isEmpty) return;
    zoomBy(factor, _viewportSize.center(Offset.zero));
  }

  void setScale(double value) {
    final next = value.clamp(minScale, maxScale).toDouble();
    if (next == _scale || _viewportSize.isEmpty) return;
    zoomAtCenter(next / _scale);
  }

  /// Frames the whole canvas with a little breathing room.
  void fitToCanvas(EditorFloor floor, {double padding = 48}) {
    if (_viewportSize.isEmpty) return;
    final availableWidth = math.max(1.0, _viewportSize.width - padding * 2);
    final availableHeight = math.max(1.0, _viewportSize.height - padding * 2);
    final scale = math
        .min(
          availableWidth / floor.canvasWidth,
          availableHeight / floor.canvasHeight,
        )
        .clamp(minScale, maxScale)
        .toDouble();
    _scale = scale;
    _offset = Offset(
      (_viewportSize.width - floor.canvasWidth * scale) / 2,
      (_viewportSize.height - floor.canvasHeight * scale) / 2,
    );
    notifyListeners();
  }
}
