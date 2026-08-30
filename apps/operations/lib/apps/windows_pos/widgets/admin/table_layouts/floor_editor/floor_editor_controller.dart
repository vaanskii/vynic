import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'package:vynic/core/models/table_layout.dart';
import 'floor_editor_model.dart';
import 'floor_editor_presets.dart';

enum EditorTool { select, place }

enum EditorGesture { none, move, resize, rotate, marquee, drawSegment }

/// The eight resize grips, named in the object's own (unrotated) space.
enum ResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

enum AlignAxis { left, centerX, right, top, centerY, bottom }

/// A snap line the canvas draws while objects are being dragged into
/// alignment with their neighbours.
@immutable
class AlignmentGuide {
  const AlignmentGuide({required this.isVertical, required this.position});

  final bool isVertical;
  final double position;
}

@immutable
class _HistoryEntry {
  const _HistoryEntry({
    required this.document,
    required this.activeFloorId,
    required this.selection,
  });

  final EditorDocument document;
  final String activeFloorId;
  final Set<String> selection;
}

/// Owns everything the floor editor edits: the document, the selection, the
/// active tool, grid/snap preferences and the undo stack.
///
/// Persistence is deliberately *not* here — the screen calls [toLayout] on an
/// explicit Save. Dragging never touches Hive.
class FloorEditorController extends ChangeNotifier {
  static const Uuid _uuid = Uuid();

  FloorEditorController({
    required RestaurantTableLayout layout,
    required String initialFloorId,
  }) : _document = EditorDocument.fromLayout(layout) {
    _activeFloorId = _document.floorById(initialFloorId) != null
        ? initialFloorId
        : (_document.floors.isEmpty ? '' : _document.floors.first.zoneId);
  }

  // ------------------------------------------------------------- document

  EditorDocument _document;
  late String _activeFloorId;
  bool _dirty = false;

  EditorDocument get document => _document;

  String get activeFloorId => _activeFloorId;

  EditorFloor get floor =>
      _document.floorById(_activeFloorId) ?? _document.floors.first;

  bool get isDirty => _dirty;

  // ------------------------------------------------------------ selection

  final Set<String> _selection = <String>{};

  Set<String> get selection => Set.unmodifiable(_selection);

  bool isSelected(String id) => _selection.contains(id);

  List<EditorObject> get selectedObjects => [
    for (final object in floor.objects)
      if (_selection.contains(object.id)) object,
  ];

  EditorObject? get singleSelection {
    final selected = selectedObjects;
    return selected.length == 1 ? selected.first : null;
  }

  // ----------------------------------------------------------- tool state

  EditorTool _tool = EditorTool.select;
  EditorPlacementSpec? _pendingSpec;

  EditorTool get tool => _tool;

  EditorPlacementSpec? get pendingSpec => _pendingSpec;

  bool get isPlacingSegment => _pendingSpec?.isSegment ?? false;

  void selectTool(EditorTool value) {
    if (_tool == value) {
      return;
    }
    _tool = value;
    if (value == EditorTool.select) {
      _pendingSpec = null;
    }
    notifyListeners();
  }

  void armPlacement(EditorPlacementSpec spec) {
    _pendingSpec = spec;
    _tool = EditorTool.place;
    notifyListeners();
  }

  void cancelPlacement() {
    if (_tool == EditorTool.select && _pendingSpec == null) {
      return;
    }
    _tool = EditorTool.select;
    _pendingSpec = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ grid/snap

  bool _gridVisible = true;
  bool _snapEnabled = true;
  double _gridSize = EditorPresets.gridStep;

  bool get gridVisible => _gridVisible;

  bool get snapEnabled => _snapEnabled;

  double get gridSize => _gridSize;

  void setGridVisible(bool value) {
    if (_gridVisible == value) return;
    _gridVisible = value;
    notifyListeners();
  }

  void setSnapEnabled(bool value) {
    if (_snapEnabled == value) return;
    _snapEnabled = value;
    notifyListeners();
  }

  void setGridSize(double value) {
    final next = value.clamp(5.0, 100.0).toDouble();
    if (_gridSize == next) return;
    _gridSize = next;
    notifyListeners();
  }

  // ------------------------------------------------------- transient drag

  EditorGesture _gesture = EditorGesture.none;
  Offset _gestureOrigin = Offset.zero;
  ResizeHandle _activeHandle = ResizeHandle.bottomRight;
  Map<String, EditorObject> _gestureSnapshot = const {};
  Rect? _marquee;
  Offset? _segmentStart;
  Offset? _segmentEnd;
  List<AlignmentGuide> _guides = const [];
  double _rotationOrigin = 0;

  EditorGesture get gesture => _gesture;

  Rect? get marqueeRect => _marquee;

  List<AlignmentGuide> get alignmentGuides => _guides;

  /// Live wall/divider preview while the pointer is down.
  (Offset, Offset)? get segmentPreview {
    final start = _segmentStart;
    final end = _segmentEnd;
    if (start == null || end == null) return null;
    return (start, end);
  }

  bool get isInteracting => _gesture != EditorGesture.none;

  // -------------------------------------------------------------- history

  final List<_HistoryEntry> _undoStack = [];
  final List<_HistoryEntry> _redoStack = [];
  static const int _historyLimit = 120;

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  /// Snapshots current state so the *next* mutation can be undone. Called
  /// once per logical operation — a whole drag, not every pointer frame.
  void _pushHistory() {
    _undoStack.add(
      _HistoryEntry(
        document: _document,
        activeFloorId: _activeFloorId,
        selection: {..._selection},
      ),
    );
    if (_undoStack.length > _historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(
      _HistoryEntry(
        document: _document,
        activeFloorId: _activeFloorId,
        selection: {..._selection},
      ),
    );
    _restore(entry);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(
      _HistoryEntry(
        document: _document,
        activeFloorId: _activeFloorId,
        selection: {..._selection},
      ),
    );
    _restore(entry);
  }

  void _restore(_HistoryEntry entry) {
    _document = entry.document;
    _activeFloorId = entry.activeFloorId;
    _selection
      ..clear()
      ..addAll(entry.selection);
    _dirty = true;
    notifyListeners();
  }

  void markSaved() {
    _dirty = false;
    notifyListeners();
  }

  // ------------------------------------------------------------- mutation

  void _replaceObjects(List<EditorObject> objects, {bool markDirty = true}) {
    _document = _document.replaceFloor(floor.copyWith(objects: objects));
    if (markDirty) {
      _dirty = true;
    }
  }

  /// Applies [transform] to every selected object, in one history step.
  void _mutateSelected(EditorObject Function(EditorObject) transform) {
    if (_selection.isEmpty) return;
    _pushHistory();
    _replaceObjects([
      for (final object in floor.objects)
        if (_selection.contains(object.id)) transform(object) else object,
    ]);
    notifyListeners();
  }

  void setActiveFloor(String zoneId) {
    if (_activeFloorId == zoneId || _document.floorById(zoneId) == null) {
      return;
    }
    _activeFloorId = zoneId;
    _selection.clear();
    _endGestureState();
    notifyListeners();
  }

  void setFloorName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == floor.name) return;
    _pushHistory();
    _document = _document.replaceFloor(floor.copyWith(name: trimmed));
    _dirty = true;
    notifyListeners();
  }

  void setCanvasSize({double? width, double? height}) {
    final nextWidth = (width ?? floor.canvasWidth).clamp(400.0, 4000.0);
    final nextHeight = (height ?? floor.canvasHeight).clamp(400.0, 4000.0);
    if (nextWidth == floor.canvasWidth && nextHeight == floor.canvasHeight) {
      return;
    }
    _pushHistory();
    _document = _document.replaceFloor(
      floor.copyWith(
        canvasWidth: nextWidth.toDouble(),
        canvasHeight: nextHeight.toDouble(),
      ),
    );
    _dirty = true;
    notifyListeners();
  }

  /// Reshapes the canvas so its aspect ratio matches [aspect] (width/height).
  ///
  /// The height is the anchor and the width follows the ratio, so switching
  /// presets is reversible — 16:10 → 16:9 → 4:3 → 16:10 lands back on the size
  /// you started from instead of ratcheting the canvas larger each time.
  ///
  /// The only exception is content that would fall outside the new shape: then
  /// the canvas grows just enough to keep every object inside, because
  /// shrinking past them would strand tables the layout save path protects.
  ///
  /// Why this matters: both the POS and this editor fit a floor with
  /// `min(scaleX, scaleY)` to preserve proportions, so a canvas shaped unlike
  /// the plan panel is letterboxed and the spare width becomes dead margin on
  /// the operational screen.
  void fitCanvasToAspect(double aspect) {
    if (aspect <= 0) return;
    final current = floor.canvasWidth / floor.canvasHeight;
    if ((current - aspect).abs() < 0.005) return;

    var height = floor.canvasHeight;
    var width = height * aspect;

    final content = floor.contentBounds;
    if (content != null) {
      if (width < content.right) {
        width = content.right;
        height = width / aspect;
      }
      if (height < content.bottom) {
        height = content.bottom;
        width = height * aspect;
      }
    }

    width = width.clamp(400.0, 4000.0).roundToDouble();
    height = height.clamp(400.0, 4000.0).roundToDouble();

    _pushHistory();
    _document = _document.replaceFloor(
      floor.copyWith(canvasWidth: width, canvasHeight: height),
    );
    _dirty = true;
    notifyListeners();
  }

  void setLayoutName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == _document.name) return;
    _pushHistory();
    _document = _document.copyWith(name: trimmed);
    _dirty = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ selection

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  void selectOnly(String id) {
    if (_selection.length == 1 && _selection.contains(id)) return;
    _selection
      ..clear()
      ..add(id);
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (!_selection.remove(id)) {
      _selection.add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    final ids = [for (final object in floor.objects) object.id];
    if (ids.length == _selection.length && _selection.containsAll(ids)) {
      return;
    }
    _selection
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  /// Topmost object under [world]. Zones are backdrops, so they only match
  /// when nothing else does — otherwise they would swallow every tap.
  EditorObject? hitTest(Offset world, {double tolerance = 0}) {
    EditorObject? backdrop;
    for (final object in floor.objects.reversed) {
      if (!object.containsWorldPoint(world, tolerance: tolerance)) {
        continue;
      }
      if (object.isBackdrop) {
        backdrop ??= object;
        continue;
      }
      return object;
    }
    return backdrop;
  }

  // ----------------------------------------------------------- placement

  /// Drops the armed preset centred on [world]. Returns the new object's id.
  String? placeAt(Offset world) {
    final spec = _pendingSpec;
    if (spec == null || spec.isSegment) return null;

    _pushHistory();
    final id = _newObjectId(spec.type);
    final legacyNumber = spec.isTable ? floor.nextLegacyTableNumber() : null;
    final position = _clampToCanvas(
      Offset(world.dx - spec.width / 2, world.dy - spec.height / 2),
      Size(spec.width, spec.height),
    );
    final snapped = _snapEnabled ? _snapOffset(position) : position;

    final object = EditorObject(
      id: id,
      type: spec.type,
      label: _labelFor(spec, legacyNumber),
      x: snapped.dx,
      y: snapped.dy,
      width: spec.width,
      height: spec.height,
      tableShape: spec.tableShape,
      capacity: spec.capacity,
      legacyTableNumber: legacyNumber,
      tableDefinitionId: legacyNumber == null ? null : _uuid.v4(),
    );

    // Zones go to the bottom so they never cover the tables inside them.
    final objects = [...floor.objects];
    if (object.isZone) {
      objects.insert(0, object);
    } else {
      objects.add(object);
    }
    _replaceObjects(objects);
    _selection
      ..clear()
      ..add(id);
    // One-shot: the tool returns to Select so the just-placed object can be
    // adjusted immediately, which is what every layout tool does.
    _tool = EditorTool.select;
    _pendingSpec = null;
    notifyListeners();
    return id;
  }

  String _labelFor(EditorPlacementSpec spec, String? legacyNumber) {
    final seed = spec.nameSeed;
    if (spec.isTable) {
      return '${seed ?? 'T'}${legacyNumber ?? ''}';
    }
    if (seed == null) {
      return spec.label;
    }
    final existing = floor.objects
        .where((object) => object.type == spec.type)
        .length;
    return existing == 0 ? seed : '$seed ${existing + 1}';
  }

  String _newObjectId(RestaurantLayoutObjectType type) {
    return '${type.name}-${DateTime.now().microsecondsSinceEpoch}-'
        '${floor.objects.length}';
  }

  // ------------------------------------------------------------- gestures

  void beginMove(Offset world) {
    if (_selection.isEmpty) return;
    _gesture = EditorGesture.move;
    _gestureOrigin = world;
    _snapshotSelection();
    notifyListeners();
  }

  void updateMove(Offset world) {
    if (_gesture != EditorGesture.move) return;
    var delta = world - _gestureOrigin;
    delta = _constrainGroupDelta(delta);

    final guides = <AlignmentGuide>[];
    if (_snapEnabled) {
      delta = _snapGroupDelta(delta, guides);
    }

    _guides = guides;
    _replaceObjects([
      for (final object in floor.objects)
        if (_gestureSnapshot[object.id] case final EditorObject origin)
          object.copyWith(x: origin.x + delta.dx, y: origin.y + delta.dy)
        else
          object,
    ]);
    notifyListeners();
  }

  void beginResize(ResizeHandle handle, Offset world) {
    if (_selection.isEmpty) return;
    _gesture = EditorGesture.resize;
    _activeHandle = handle;
    _gestureOrigin = world;
    _snapshotSelection();
    notifyListeners();
  }

  void updateResize(Offset world) {
    if (_gesture != EditorGesture.resize) return;
    _replaceObjects([
      for (final object in floor.objects)
        if (_gestureSnapshot[object.id] case final EditorObject origin)
          _resized(origin, world)
        else
          object,
    ]);
    notifyListeners();
  }

  EditorObject _resized(EditorObject origin, Offset world) {
    // Resize maths happen in the object's own space, so a rotated table
    // still grows along its own edges rather than the screen axes.
    final localPointer = origin.toLocal(world);
    final localStart = origin.toLocal(_gestureOrigin);
    final delta = localPointer - localStart;
    final minimum = EditorPresets.minimumSize(origin.type);

    var left = origin.x;
    var top = origin.y;
    var right = origin.x + origin.width;
    var bottom = origin.y + origin.height;

    switch (_activeHandle) {
      case ResizeHandle.topLeft:
        left += delta.dx;
        top += delta.dy;
      case ResizeHandle.top:
        top += delta.dy;
      case ResizeHandle.topRight:
        right += delta.dx;
        top += delta.dy;
      case ResizeHandle.right:
        right += delta.dx;
      case ResizeHandle.bottomRight:
        right += delta.dx;
        bottom += delta.dy;
      case ResizeHandle.bottom:
        bottom += delta.dy;
      case ResizeHandle.bottomLeft:
        left += delta.dx;
        bottom += delta.dy;
      case ResizeHandle.left:
        left += delta.dx;
    }

    if (_snapEnabled) {
      left = _snapValue(left);
      top = _snapValue(top);
      right = _snapValue(right);
      bottom = _snapValue(bottom);
    }

    if (right - left < minimum.width) {
      if (_movesLeftEdge(_activeHandle)) {
        left = right - minimum.width;
      } else {
        right = left + minimum.width;
      }
    }
    if (bottom - top < minimum.height) {
      if (_movesTopEdge(_activeHandle)) {
        top = bottom - minimum.height;
      } else {
        bottom = top + minimum.height;
      }
    }

    // Circles and bar seats stay circular: one dimension drives both.
    if (origin.isTable &&
        (origin.tableShape == RestaurantTableShape.circle ||
            origin.tableShape == RestaurantTableShape.barSeat)) {
      final size = math.max(right - left, bottom - top);
      if (_movesLeftEdge(_activeHandle)) {
        left = right - size;
      } else {
        right = left + size;
      }
      if (_movesTopEdge(_activeHandle)) {
        top = bottom - size;
      } else {
        bottom = top + size;
      }
    }

    // Rotating around the centre means the centre must stay put, or the
    // object would slide sideways as it grows.
    final newWidth = right - left;
    final newHeight = bottom - top;
    final oldCenter = origin.center;
    final localCenter = Offset(left + newWidth / 2, top + newHeight / 2);
    final angle = origin.rotationRadians;
    final shift = localCenter - oldCenter;
    final rotatedShift = Offset(
      shift.dx * math.cos(angle) - shift.dy * math.sin(angle),
      shift.dx * math.sin(angle) + shift.dy * math.cos(angle),
    );
    final newCenter = oldCenter + rotatedShift;

    return origin.copyWith(
      x: newCenter.dx - newWidth / 2,
      y: newCenter.dy - newHeight / 2,
      width: newWidth,
      height: newHeight,
    );
  }

  static bool _movesLeftEdge(ResizeHandle handle) {
    return handle == ResizeHandle.topLeft ||
        handle == ResizeHandle.left ||
        handle == ResizeHandle.bottomLeft;
  }

  static bool _movesTopEdge(ResizeHandle handle) {
    return handle == ResizeHandle.topLeft ||
        handle == ResizeHandle.top ||
        handle == ResizeHandle.topRight;
  }

  void beginRotate(Offset world) {
    final target = singleSelection;
    if (target == null) return;
    _gesture = EditorGesture.rotate;
    _snapshotSelection();
    final vector = world - target.center;
    _rotationOrigin =
        math.atan2(vector.dy, vector.dx) * 180 / math.pi - target.rotation;
    notifyListeners();
  }

  void updateRotate(Offset world) {
    if (_gesture != EditorGesture.rotate) return;
    _replaceObjects([
      for (final object in floor.objects)
        if (_gestureSnapshot[object.id] case final EditorObject origin)
          origin.copyWith(rotation: _rotationFor(origin, world))
        else
          object,
    ]);
    notifyListeners();
  }

  double _rotationFor(EditorObject origin, Offset world) {
    final vector = world - origin.center;
    var degrees =
        math.atan2(vector.dy, vector.dx) * 180 / math.pi - _rotationOrigin;
    if (_snapEnabled) {
      // 15° steps, which contains the 0/45/90/135/180 detents that matter
      // for aligning booths and bars against walls.
      degrees = (degrees / 15).roundToDouble() * 15;
    }
    return _normalizeDegrees(degrees);
  }

  static double _normalizeDegrees(double value) {
    final wrapped = value % 360;
    return wrapped < 0 ? wrapped + 360 : wrapped;
  }

  void beginMarquee(Offset world) {
    _gesture = EditorGesture.marquee;
    _gestureOrigin = world;
    _marquee = Rect.fromPoints(world, world);
    notifyListeners();
  }

  void updateMarquee(Offset world, {bool additive = false}) {
    if (_gesture != EditorGesture.marquee) return;
    final rect = Rect.fromPoints(_gestureOrigin, world);
    _marquee = rect;
    final hits = <String>{
      for (final object in floor.objects)
        if (rect.overlaps(object.boundingBox)) object.id,
    };
    if (!additive) {
      _selection.clear();
    }
    _selection.addAll(hits);
    notifyListeners();
  }

  void beginSegment(Offset world) {
    _gesture = EditorGesture.drawSegment;
    final start = _snapEnabled ? _snapOffset(world) : world;
    _segmentStart = start;
    _segmentEnd = start;
    notifyListeners();
  }

  void updateSegment(Offset world) {
    if (_gesture != EditorGesture.drawSegment) return;
    var end = _snapEnabled ? _snapOffset(world) : world;
    final start = _segmentStart;
    if (start != null && _snapEnabled) {
      end = _snapSegmentAngle(start, end);
    }
    _segmentEnd = end;
    notifyListeners();
  }

  /// Straightens a nearly-horizontal/vertical/diagonal drag so walls come
  /// out square without demanding a steady hand.
  Offset _snapSegmentAngle(Offset start, Offset end) {
    final vector = end - start;
    if (vector.distance < 1) return end;
    final degrees = math.atan2(vector.dy, vector.dx) * 180 / math.pi;
    final snapped = (degrees / 45).roundToDouble() * 45;
    if ((degrees - snapped).abs() > 8) {
      return end;
    }
    final radians = snapped * math.pi / 180;
    return start +
        Offset(math.cos(radians), math.sin(radians)) * vector.distance;
  }

  /// Commits whatever gesture is in flight as exactly one history entry.
  void endGesture() {
    switch (_gesture) {
      case EditorGesture.none:
      case EditorGesture.marquee:
        break;
      case EditorGesture.move:
      case EditorGesture.resize:
      case EditorGesture.rotate:
        _commitGestureIfChanged();
      case EditorGesture.drawSegment:
        _commitSegment();
    }
    _endGestureState();
    notifyListeners();
  }

  /// The history push happens *here*, at the end, using the snapshot taken
  /// when the drag began — that is what makes one drag one undo step.
  void _commitGestureIfChanged() {
    var changed = false;
    for (final object in floor.objects) {
      final origin = _gestureSnapshot[object.id];
      if (origin == null) continue;
      if (origin.x != object.x ||
          origin.y != object.y ||
          origin.width != object.width ||
          origin.height != object.height ||
          origin.rotation != object.rotation) {
        changed = true;
        break;
      }
    }
    if (!changed) {
      return;
    }
    final current = floor.objects;
    // Rewind to the pre-drag state, record it, then re-apply — so undo
    // returns to where the drag started rather than mid-drag.
    _replaceObjects([
      for (final object in current) _gestureSnapshot[object.id] ?? object,
    ], markDirty: false);
    _pushHistory();
    _replaceObjects(current);
  }

  void _commitSegment() {
    final spec = _pendingSpec;
    final start = _segmentStart;
    final end = _segmentEnd;
    if (spec == null || start == null || end == null) return;

    final vector = end - start;
    final length = vector.distance;
    if (length < 18) {
      // Too short to be intentional — treat as a mis-click, not a 2px wall.
      return;
    }

    _pushHistory();
    final thickness = spec.height;
    final center = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final object = EditorObject(
      id: _newObjectId(spec.type),
      type: spec.type,
      label: spec.label,
      x: center.dx - length / 2,
      y: center.dy - thickness / 2,
      width: length,
      height: thickness,
      rotation: _normalizeDegrees(
        math.atan2(vector.dy, vector.dx) * 180 / math.pi,
      ),
    );
    _replaceObjects([...floor.objects, object]);
    _selection
      ..clear()
      ..add(object.id);
    // Walls come in runs, so the segment tool stays armed after each one.
  }

  void _endGestureState() {
    _gesture = EditorGesture.none;
    _gestureSnapshot = const {};
    _marquee = null;
    _segmentStart = null;
    _segmentEnd = null;
    _guides = const [];
  }

  void cancelGesture() {
    if (_gesture == EditorGesture.none) return;
    if (_gestureSnapshot.isNotEmpty) {
      _replaceObjects([
        for (final object in floor.objects)
          _gestureSnapshot[object.id] ?? object,
      ], markDirty: false);
    }
    _endGestureState();
    notifyListeners();
  }

  void _snapshotSelection() {
    _gestureSnapshot = {
      for (final object in floor.objects)
        if (_selection.contains(object.id)) object.id: object,
    };
  }

  // -------------------------------------------------------------- snapping

  double _snapValue(double value) =>
      (value / _gridSize).roundToDouble() * _gridSize;

  Offset _snapOffset(Offset value) =>
      Offset(_snapValue(value.dx), _snapValue(value.dy));

  /// Keeps a multi-object drag inside the canvas without letting one object
  /// hitting the wall shear the group apart.
  Offset _constrainGroupDelta(Offset delta) {
    if (_gestureSnapshot.isEmpty) return delta;
    var minDx = double.negativeInfinity;
    var maxDx = double.infinity;
    var minDy = double.negativeInfinity;
    var maxDy = double.infinity;

    for (final origin in _gestureSnapshot.values) {
      final bounds = origin.boundingBox;
      minDx = math.max(minDx, -bounds.left);
      maxDx = math.min(maxDx, floor.canvasWidth - bounds.right);
      minDy = math.max(minDy, -bounds.top);
      maxDy = math.min(maxDy, floor.canvasHeight - bounds.bottom);
    }

    return Offset(
      delta.dx.clamp(math.min(minDx, maxDx), math.max(minDx, maxDx)),
      delta.dy.clamp(math.min(minDy, maxDy), math.max(minDy, maxDy)),
    );
  }

  /// Grid snap plus lightweight edge/centre alignment against the objects
  /// that are *not* being dragged.
  Offset _snapGroupDelta(Offset delta, List<AlignmentGuide> guides) {
    if (_gestureSnapshot.isEmpty) return delta;

    final moved = _gestureSnapshot.values
        .map((origin) => origin.boundingBox.shift(delta))
        .toList();
    var groupBounds = moved.first;
    for (final bounds in moved.skip(1)) {
      groupBounds = groupBounds.expandToInclude(bounds);
    }

    const threshold = 7.0;
    double? bestDx;
    double? bestDy;
    var bestDxDistance = threshold;
    var bestDyDistance = threshold;
    AlignmentGuide? verticalGuide;
    AlignmentGuide? horizontalGuide;

    for (final other in floor.objects) {
      if (_gestureSnapshot.containsKey(other.id)) continue;
      final target = other.boundingBox;

      for (final pair in <(double, double)>[
        (groupBounds.left, target.left),
        (groupBounds.center.dx, target.center.dx),
        (groupBounds.right, target.right),
        (groupBounds.left, target.right),
        (groupBounds.right, target.left),
      ]) {
        final distance = (pair.$1 - pair.$2).abs();
        if (distance < bestDxDistance) {
          bestDxDistance = distance;
          bestDx = pair.$2 - pair.$1;
          verticalGuide = AlignmentGuide(isVertical: true, position: pair.$2);
        }
      }

      for (final pair in <(double, double)>[
        (groupBounds.top, target.top),
        (groupBounds.center.dy, target.center.dy),
        (groupBounds.bottom, target.bottom),
        (groupBounds.top, target.bottom),
        (groupBounds.bottom, target.top),
      ]) {
        final distance = (pair.$1 - pair.$2).abs();
        if (distance < bestDyDistance) {
          bestDyDistance = distance;
          bestDy = pair.$2 - pair.$1;
          horizontalGuide = AlignmentGuide(
            isVertical: false,
            position: pair.$2,
          );
        }
      }
    }

    if (verticalGuide != null) guides.add(verticalGuide);
    if (horizontalGuide != null) guides.add(horizontalGuide);

    // Neighbour alignment wins over the grid; falling back to the grid keeps
    // free-floating objects tidy.
    final dx = bestDx != null
        ? delta.dx + bestDx
        : delta.dx + (_snapValue(groupBounds.left) - groupBounds.left);
    final dy = bestDy != null
        ? delta.dy + bestDy
        : delta.dy + (_snapValue(groupBounds.top) - groupBounds.top);
    return _constrainGroupDelta(Offset(dx, dy));
  }

  Offset _clampToCanvas(Offset position, Size size) {
    return Offset(
      position.dx.clamp(0.0, math.max(0.0, floor.canvasWidth - size.width)),
      position.dy.clamp(0.0, math.max(0.0, floor.canvasHeight - size.height)),
    );
  }

  // --------------------------------------------------------------- actions

  void nudgeSelection(double dx, double dy) {
    if (_selection.isEmpty) return;
    _mutateSelected(
      (object) => object.copyWith(x: object.x + dx, y: object.y + dy),
    );
  }

  void rotateSelectionBy(double degrees) {
    if (_selection.isEmpty) return;
    _mutateSelected(
      (object) => object.copyWith(
        rotation: _normalizeDegrees(object.rotation + degrees),
      ),
    );
  }

  void deleteSelection() {
    if (_selection.isEmpty) return;
    _pushHistory();
    _replaceObjects([
      for (final object in floor.objects)
        if (!_selection.contains(object.id)) object,
    ]);
    _selection.clear();
    notifyListeners();
  }

  void duplicateSelection() {
    if (_selection.isEmpty) return;
    _pushHistory();

    final objects = [...floor.objects];
    final created = <String>[];
    // Table numbers must stay unique per floor, so allocate as we go rather
    // than reading `nextLegacyTableNumber` against the stale list.
    final usedNumbers = <int>{
      for (final table in floor.tables)
        if (int.tryParse(table.legacyTableNumber ?? '') case final int n) n,
    };

    for (final object in floor.objects) {
      if (!_selection.contains(object.id)) continue;

      String? legacyNumber;
      String? definitionId;
      var label = object.label;
      if (object.isTable) {
        var candidate = 1;
        while (usedNumbers.contains(candidate)) {
          candidate++;
        }
        usedNumbers.add(candidate);
        legacyNumber = '$candidate';
        definitionId = _uuid.v4();
        label = _duplicateLabel(object.label, legacyNumber);
      }

      final copy = object.duplicated(
        newId: '${_newObjectId(object.type)}-${created.length}',
        newLegacyTableNumber: legacyNumber,
        newTableDefinitionId: definitionId,
        newLabel: label,
        dx: _gridSize,
        dy: _gridSize,
      );
      objects.add(copy);
      created.add(copy.id);
    }

    _replaceObjects(objects);
    _selection
      ..clear()
      ..addAll(created);
    notifyListeners();
  }

  /// "T4" duplicated with number 9 becomes "T9"; a hand-written name like
  /// "VIP corner" becomes "VIP corner 9" rather than being silently reused.
  static String _duplicateLabel(String source, String number) {
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(source.trim());
    if (match != null) {
      return '${match.group(1)}$number';
    }
    return '${source.trim()} $number';
  }

  void updateSelectedLabel(String label) {
    final target = singleSelection;
    if (target == null || target.label == label.trim()) return;
    _mutateSelected((object) => object.copyWith(label: label.trim()));
  }

  void updateSelectedCapacity(int capacity) {
    _mutateSelected(
      (object) => object.isTable
          ? object.copyWith(capacity: math.max(0, capacity))
          : object,
    );
  }

  void updateSelectedShape(RestaurantTableShape shape) {
    _mutateSelected((object) {
      if (!object.isTable) return object;
      // Round shapes must not inherit a rectangle's aspect ratio.
      if (shape == RestaurantTableShape.circle ||
          shape == RestaurantTableShape.barSeat ||
          shape == RestaurantTableShape.square) {
        final size = math.max(object.width, object.height);
        return object.copyWith(
          tableShape: shape,
          width: size,
          height: size,
          x: object.center.dx - size / 2,
          y: object.center.dy - size / 2,
        );
      }
      return object.copyWith(tableShape: shape);
    });
  }

  void updateSelectedSize({double? width, double? height}) {
    _mutateSelected((object) {
      final minimum = EditorPresets.minimumSize(object.type);
      final nextWidth = math.max(minimum.width, width ?? object.width);
      final nextHeight = math.max(minimum.height, height ?? object.height);
      final center = object.center;
      return object.copyWith(
        width: nextWidth,
        height: nextHeight,
        x: center.dx - nextWidth / 2,
        y: center.dy - nextHeight / 2,
      );
    });
  }

  void updateSelectedRotation(double degrees) {
    _mutateSelected(
      (object) => object.copyWith(rotation: _normalizeDegrees(degrees)),
    );
  }

  // ------------------------------------------------------------- alignment

  void align(AlignAxis axis) {
    if (_selection.length < 2) return;
    final targets = selectedObjects;
    var bounds = targets.first.boundingBox;
    for (final object in targets.skip(1)) {
      bounds = bounds.expandToInclude(object.boundingBox);
    }

    _mutateSelected((object) {
      final box = object.boundingBox;
      switch (axis) {
        case AlignAxis.left:
          return object.copyWith(x: object.x + (bounds.left - box.left));
        case AlignAxis.centerX:
          return object.copyWith(
            x: object.x + (bounds.center.dx - box.center.dx),
          );
        case AlignAxis.right:
          return object.copyWith(x: object.x + (bounds.right - box.right));
        case AlignAxis.top:
          return object.copyWith(y: object.y + (bounds.top - box.top));
        case AlignAxis.centerY:
          return object.copyWith(
            y: object.y + (bounds.center.dy - box.center.dy),
          );
        case AlignAxis.bottom:
          return object.copyWith(y: object.y + (bounds.bottom - box.bottom));
      }
    });
  }

  void distribute({required bool horizontal}) {
    if (_selection.length < 3) return;
    final targets = [...selectedObjects]
      ..sort((a, b) {
        return horizontal
            ? a.boundingBox.center.dx.compareTo(b.boundingBox.center.dx)
            : a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy);
      });

    final first = targets.first.boundingBox;
    final last = targets.last.boundingBox;
    final span = horizontal
        ? last.center.dx - first.center.dx
        : last.center.dy - first.center.dy;
    final step = span / (targets.length - 1);

    final shifts = <String, double>{};
    for (var i = 1; i < targets.length - 1; i++) {
      final box = targets[i].boundingBox;
      final wanted =
          (horizontal ? first.center.dx : first.center.dy) + step * i;
      final actual = horizontal ? box.center.dx : box.center.dy;
      shifts[targets[i].id] = wanted - actual;
    }
    if (shifts.isEmpty) return;

    _pushHistory();
    _replaceObjects([
      for (final object in floor.objects)
        if (shifts[object.id] case final double shift)
          object.copyWith(
            x: horizontal ? object.x + shift : object.x,
            y: horizontal ? object.y : object.y + shift,
          )
        else
          object,
    ]);
    notifyListeners();
  }

  // ------------------------------------------------------------------ save

  /// The floor that was opened here now has real floor-plan geometry, so it
  /// is written as [TableLayoutRenderMode.floorPlan] regardless of how it
  /// used to render. Every other floor keeps its own mode untouched.
  RestaurantTableLayout toLayout() {
    final edited = floor;
    if (edited.renderMode == TableLayoutRenderMode.floorPlan) {
      return _document.toLayout();
    }
    return _document
        .replaceFloor(
          edited.copyWith(renderMode: TableLayoutRenderMode.floorPlan),
        )
        .toLayout();
  }
}
