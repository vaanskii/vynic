import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_controller.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_model.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/table_layouts/floor_editor/floor_editor_presets.dart';
import 'package:vynic/core/contracts/table_identity.dart' as contract;
import 'package:vynic/core/models/table_layout.dart';

/// The editor is a view over the legacy layout model, so these tests are
/// mostly about the adapter holding its end of the bargain: whatever an
/// admin does on the canvas, `(legacyFloor, legacyTableNumber)` — the key
/// orders, reservations and live table rows are stored against — survives.

FloorEditorController _controllerFor(
  RestaurantTableLayout layout, {
  bool snap = false,
}) {
  final controller = FloorEditorController(
    layout: layout,
    initialFloorId: layout.zones.first.id,
  )..setSnapEnabled(snap);
  return controller;
}

void main() {
  group('EditorDocument round trip', () {
    test('loads the built-in floor plan layout', () {
      final document = EditorDocument.fromLayout(
        RestaurantTableLayouts.floorPlanPreview,
      );

      expect(document.floors, hasLength(2));
      expect(document.floors.first.tableCount, greaterThan(0));
      for (final floor in document.floors) {
        for (final table in floor.tables) {
          expect(table.legacyTableNumber, isNotNull);
          expect(table.tableDefinitionId, isNotNull);
        }
      }
    });

    test('gives a button-grid layout real geometry to open with', () {
      // A button-grid layout stores no floor-plan objects at all; without the
      // fallback grid, opening it in the editor would show an empty canvas.
      // (This used to be the SVG layout, whose tables carried hit boxes.)
      final document = EditorDocument.fromLayout(
        RestaurantTableLayouts.buttonGridPreview,
      );
      final tables = document.floors.first.tables.toList();

      expect(tables, isNotEmpty);
      for (final table in tables) {
        expect(table.width, greaterThan(0));
        expect(table.height, greaterThan(0));
      }
    });

    test('preserves legacy identity and render mode through a round trip', () {
      final original = RestaurantTableLayouts.buttonGridPreview;
      final rebuilt = EditorDocument.fromLayout(original).toLayout();

      expect(
        rebuilt.tables.map((table) => table.legacyTableNumber),
        original.tables.map((table) => table.legacyTableNumber),
      );
      expect(
        rebuilt.tables.map((table) => table.legacyFloor),
        original.tables.map((table) => table.legacyFloor),
      );
      // An untouched floor keeps rendering the way it always did.
      expect(
        rebuilt.zones.map((zone) => zone.renderMode),
        original.zones.map((zone) => zone.renderMode),
      );
    });

    test('keeps table identity when its label and position change', () {
      final original = RestaurantTableLayouts.floorPlanPreview;
      final table = original.tables.first;
      final object = original.objectForTable(table.id)!;
      final controller = _controllerFor(original, snap: false);

      controller.selectOnly(object.id);
      controller.updateSelectedLabel('Window table');
      controller.nudgeSelection(37, 19);

      final rebuilt = controller.toLayout();
      final changedTable = rebuilt.tableForId(table.id);
      final changedObject = rebuilt.objectForTable(table.id);

      expect(changedTable, isNotNull);
      expect(changedTable!.id, table.id);
      expect(changedTable.label, 'Window table');
      expect(changedObject, isNotNull);
      expect(changedObject!.x, object.x + 37);
      expect(changedObject.y, object.y + 19);
    });

    test('upgrades old IDs once and preserves every visual link', () {
      var sequence = 0;
      String nextId() {
        sequence++;
        return '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}';
      }

      final old = RestaurantTableLayouts.floorPlanPreview;
      final upgraded = old.withCanonicalTableIds(generateId: (_) => nextId());

      expect(upgraded.tables, hasLength(old.tables.length));
      expect(
        upgraded.tables.every((table) => contract.isCanonicalTableId(table.id)),
        isTrue,
      );
      expect(
        upgraded.tables.map((table) => table.legacyFloor),
        old.tables.map((table) => table.legacyFloor),
      );
      expect(
        upgraded.tables.map((table) => table.legacyTableNumber),
        old.tables.map((table) => table.legacyTableNumber),
      );
      for (final table in upgraded.tables) {
        expect(upgraded.objectForTable(table.id), isNotNull);
      }

      final reopened = RestaurantTableLayout.fromJson(
        jsonDecode(jsonEncode(upgraded)) as Map<String, dynamic>,
      );
      final repeated = reopened.withCanonicalTableIds(
        generateId: (_) => throw StateError('must not regenerate'),
      );
      expect(identical(reopened, repeated), isTrue);
      expect(
        repeated.tables.map((table) => table.id),
        upgraded.tables.map((table) => table.id),
      );
    });

    test('survives a JSON encode/decode cycle, as the settings box does', () {
      final rebuilt = EditorDocument.fromLayout(
        RestaurantTableLayouts.floorPlanPreview,
      ).toLayout();

      final decoded = RestaurantTableLayout.fromJson(
        jsonDecode(jsonEncode(rebuilt)) as Map<String, dynamic>,
      );
      final reopened = EditorDocument.fromLayout(decoded);

      expect(reopened.floors, hasLength(rebuilt.zones.length));
      expect(
        reopened.floors.first.tableCount,
        EditorDocument.fromLayout(rebuilt).floors.first.tableCount,
      );
    });

    test('the edited floor is written as a floor plan', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.buttonGridPreview,
      );
      final saved = controller.toLayout();

      final editedZone = saved.zones.firstWhere(
        (zone) => zone.id == controller.activeFloorId,
      );
      expect(editedZone.renderMode, TableLayoutRenderMode.floorPlan);
      // ...and only that one.
      final otherZone = saved.zones.firstWhere(
        (zone) => zone.id != controller.activeFloorId,
      );
      expect(otherZone.renderMode, TableLayoutRenderMode.buttonGrid);
    });
  });

  group('placement', () {
    test('a placed table gets an unused legacy number', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final existing = {
        for (final table in controller.floor.tables) table.legacyTableNumber,
      };

      controller.armPlacement(EditorPresets.groups.first.entries.first.spec);
      final id = controller.placeAt(const Offset(300, 300));

      final placed = controller.floor.objects.firstWhere((o) => o.id == id);
      expect(placed.isTable, isTrue);
      expect(existing.contains(placed.legacyTableNumber), isFalse);
      expect(placed.capacity, greaterThan(0));
      expect(contract.isCanonicalTableId(placed.tableDefinitionId!), isTrue);
    });

    test(
      'placing returns to the select tool so the object can be adjusted',
      () {
        final controller = _controllerFor(
          RestaurantTableLayouts.floorPlanPreview,
        );
        controller.armPlacement(EditorPresets.zone);
        controller.placeAt(const Offset(200, 200));

        expect(controller.tool, EditorTool.select);
        expect(controller.selection, hasLength(1));
      },
    );

    test('zones are inserted behind everything else', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.armPlacement(EditorPresets.zone);
      controller.placeAt(const Offset(300, 300));

      expect(controller.floor.objects.first.isZone, isTrue);
    });

    test('a table inside a zone reports that zone as its area', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.armPlacement(EditorPresets.zone);
      controller.placeAt(const Offset(400, 400));
      final zone = controller.floor.objects.first;

      controller.armPlacement(EditorPresets.groups.first.entries.first.spec);
      controller.placeAt(const Offset(400, 400));
      final table = controller.singleSelection!;

      expect(controller.floor.zoneAt(table.center)?.id, zone.id);
    });

    test('a drawn wall becomes one rotated segment', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.armPlacement(EditorPresets.wall);
      controller
        ..beginSegment(const Offset(100, 100))
        ..updateSegment(const Offset(300, 100))
        ..endGesture();

      final wall = controller.floor.objects.last;
      expect(wall.type, RestaurantLayoutObjectType.wall);
      expect(wall.width, closeTo(200, 0.01));
      expect(wall.height, EditorPresets.wall.height);
      expect(wall.rotation, closeTo(0, 0.01));
    });

    test('a stray click does not leave a 2px wall behind', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final before = controller.floor.objects.length;

      controller.armPlacement(EditorPresets.wall);
      controller
        ..beginSegment(const Offset(100, 100))
        ..updateSegment(const Offset(103, 100))
        ..endGesture();

      expect(controller.floor.objects, hasLength(before));
    });
  });

  group('manipulation and history', () {
    test('one drag is one undo step', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final table = controller.floor.tables.first;
      final originalX = table.x;
      controller.selectOnly(table.id);

      controller.beginMove(Offset(table.center.dx, table.center.dy));
      for (var step = 1; step <= 10; step++) {
        controller.updateMove(
          Offset(table.center.dx + step * 4, table.center.dy),
        );
      }
      controller.endGesture();

      final moved = controller.floor.objects.firstWhere(
        (o) => o.id == table.id,
      );
      expect(moved.x, closeTo(originalX + 40, 0.01));

      controller.undo();
      final restored = controller.floor.objects.firstWhere(
        (o) => o.id == table.id,
      );
      expect(restored.x, closeTo(originalX, 0.01));
      // Ten pointer frames must not have produced ten history entries.
      expect(controller.canUndo, isFalse);

      controller.redo();
      expect(
        controller.floor.objects.firstWhere((o) => o.id == table.id).x,
        closeTo(originalX + 40, 0.01),
      );
    });

    test('a drag that ends where it started records nothing', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final table = controller.floor.tables.first;
      controller.selectOnly(table.id);

      controller.beginMove(table.center);
      controller.updateMove(table.center);
      controller.endGesture();

      expect(controller.canUndo, isFalse);
    });

    test('resize honours the minimum size', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final table = controller.floor.tables.first;
      controller.selectOnly(table.id);

      controller.beginResize(ResizeHandle.right, table.rect.centerRight);
      controller.updateResize(table.rect.centerLeft - const Offset(500, 0));
      controller.endGesture();

      final resized = controller.floor.objects.firstWhere(
        (o) => o.id == table.id,
      );
      expect(
        resized.width,
        greaterThanOrEqualTo(
          EditorPresets.minimumSize(RestaurantLayoutObjectType.table).width,
        ),
      );
    });

    test('rotation snaps to 15° steps when snap is on', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
        snap: true,
      );
      final table = controller.floor.tables.first;
      controller.selectOnly(table.id);

      controller.beginRotate(table.center + const Offset(100, 0));
      controller.updateRotate(table.center + const Offset(96, 32));
      controller.endGesture();

      final rotated = controller.floor.objects.firstWhere(
        (o) => o.id == table.id,
      );
      expect(rotated.rotation % 15, closeTo(0, 0.001));
    });

    test('duplicating a table allocates a fresh legacy number', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final table = controller.floor.tables.first;
      controller.selectOnly(table.id);

      controller.duplicateSelection();

      final numbers = controller.floor.tables
          .map((t) => t.legacyTableNumber)
          .toList();
      expect(numbers.toSet(), hasLength(numbers.length));
      expect(controller.selection, hasLength(1));
      expect(controller.singleSelection!.id, isNot(table.id));
    });

    test('duplicating several tables at once keeps every number unique', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      for (final table in controller.floor.tables.take(3)) {
        controller.toggleSelection(table.id);
      }

      controller.duplicateSelection();

      final numbers = controller.floor.tables
          .map((t) => t.legacyTableNumber)
          .toList();
      expect(numbers.toSet(), hasLength(numbers.length));
    });

    test('deleting frees the number for the next table', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final table = controller.floor.tables.first;
      final freed = table.legacyTableNumber;

      controller.selectOnly(table.id);
      controller.deleteSelection();

      expect(controller.floor.nextLegacyTableNumber(), freed);
    });

    test('marquee selection picks up everything it overlaps', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.beginMarquee(Offset.zero);
      controller.updateMarquee(
        Offset(controller.floor.canvasWidth, controller.floor.canvasHeight),
      );
      controller.endGesture();

      expect(controller.selection, hasLength(controller.floor.objects.length));
    });

    test('align left puts every selected object on one edge', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      for (final table in controller.floor.tables.take(3)) {
        controller.toggleSelection(table.id);
      }

      controller.align(AlignAxis.left);

      final lefts = controller.selectedObjects
          .map((object) => object.boundingBox.left)
          .toSet();
      expect(lefts, hasLength(1));
    });

    test('distribute evens out the gaps between three objects', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final tables = controller.floor.tables.take(3).toList();
      if (tables.length < 3) {
        return;
      }
      for (final table in tables) {
        controller.toggleSelection(table.id);
      }

      controller.distribute(horizontal: true);

      final centers =
          controller.selectedObjects
              .map((object) => object.boundingBox.center.dx)
              .toList()
            ..sort();
      expect(centers[1] - centers[0], closeTo(centers[2] - centers[1], 0.01));
    });

    test('nudging is undoable and moves by one grid step', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
        snap: true,
      );
      final table = controller.floor.tables.first;
      controller.selectOnly(table.id);

      controller.nudgeSelection(controller.gridSize, 0);
      expect(
        controller.floor.objects.firstWhere((o) => o.id == table.id).x,
        closeTo(table.x + controller.gridSize, 0.01),
      );

      controller.undo();
      expect(
        controller.floor.objects.firstWhere((o) => o.id == table.id).x,
        closeTo(table.x, 0.01),
      );
    });

    test('switching a table to a round shape squares it up', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final table = controller.floor.tables.first;
      controller.selectOnly(table.id);

      controller.updateSelectedShape(RestaurantTableShape.circle);

      final updated = controller.singleSelection!;
      expect(updated.width, updated.height);
      // Resizing around the centre means it must not have wandered.
      expect(updated.center.dx, closeTo(table.center.dx, 0.01));
    });

    test('editing marks the document dirty until it is saved', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      expect(controller.isDirty, isFalse);

      controller.selectOnly(controller.floor.tables.first.id);
      controller.nudgeSelection(10, 0);
      expect(controller.isDirty, isTrue);

      controller.markSaved();
      expect(controller.isDirty, isFalse);
    });
  });

  group('hit testing', () {
    test('a zone never steals a tap from a table sitting inside it', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.armPlacement(EditorPresets.zone);
      controller.placeAt(const Offset(400, 400));

      controller.armPlacement(EditorPresets.groups.first.entries.first.spec);
      controller.placeAt(const Offset(400, 400));
      final table = controller.singleSelection!;

      expect(controller.hitTest(table.center)?.id, table.id);
    });

    test('an empty patch of zone still selects the zone', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.armPlacement(EditorPresets.zone);
      final zoneId = controller.placeAt(const Offset(500, 500));
      final zone = controller.floor.objects.firstWhere((o) => o.id == zoneId);

      expect(
        controller.hitTest(zone.rect.topLeft + const Offset(4, 4))?.id,
        zoneId,
      );
    });
  });

  group('POS compatibility', () {
    test('the operational Tables screen can resolve every edited table', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );

      // Do the things an admin would: add a table, then draw a wall.
      controller.armPlacement(EditorPresets.groups.first.entries.first.spec);
      controller.placeAt(const Offset(500, 500));
      controller.armPlacement(EditorPresets.wall);
      controller
        ..beginSegment(const Offset(60, 60))
        ..updateSegment(const Offset(360, 60))
        ..endGesture();

      final saved = controller.toLayout();

      for (final zone in saved.zones) {
        for (final definition in saved.tablesForZone(zone.id)) {
          // Exactly what TableSelectionWidget does to draw a table:
          // definition -> geometry object, and legacy pair -> live Hive row.
          final visual = saved.objectForTable(definition.id);
          expect(visual, isNotNull, reason: 'no geometry for ${definition.id}');
          expect(visual!.type, RestaurantLayoutObjectType.table);
          expect(visual.width, greaterThan(0));

          expect(
            saved.tableForLegacy(
              floor: definition.legacyFloor,
              tableNumber: definition.legacyTableNumber,
            ),
            isNotNull,
          );
        }
      }

      // And the floor/number map TableRepository reconciles against.
      final legacyMap = saved.legacyTableLayout();
      expect(
        legacyMap.keys,
        containsAll(saved.zones.map((z) => z.legacyFloor)),
      );
      for (final numbers in legacyMap.values) {
        expect(numbers.toSet(), hasLength(numbers.length));
      }
    });

    test('a new wall never lands in the table list', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final before = controller.toLayout().tables.length;

      controller.armPlacement(EditorPresets.wall);
      controller
        ..beginSegment(const Offset(60, 60))
        ..updateSegment(const Offset(360, 60))
        ..endGesture();

      expect(controller.toLayout().tables, hasLength(before));
    });
  });

  group('canvas shape', () {
    test('the built-in floors are letterboxed on a landscape terminal', () {
      // This is the defect the aspect presets exist to fix: both stock floors
      // are portrait/square, so the POS min(scaleX, scaleY) fit leaves dead
      // margins down the left and right of the plan panel.
      for (final zone in RestaurantTableLayouts.floorPlanPreview.zones) {
        final aspect = zone.canvasWidth! / zone.canvasHeight!;
        expect(aspect, lessThan(16 / 10));
      }
    });

    test('the height is the anchor; the width follows the ratio', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.fitCanvasToAspect(16 / 10);
      final height = controller.floor.canvasHeight;

      controller.fitCanvasToAspect(16 / 9);

      expect(controller.floor.canvasHeight, closeTo(height, 1));
      expect(
        controller.floor.canvasWidth / controller.floor.canvasHeight,
        closeTo(16 / 9, 0.01),
      );
    });

    test('cycling through the presets returns to the same size', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.fitCanvasToAspect(16 / 10);
      final width = controller.floor.canvasWidth;
      final height = controller.floor.canvasHeight;

      // This is the ratchet the height anchor exists to prevent: every extra
      // lap used to leave the canvas bigger than the last.
      for (var i = 0; i < 4; i++) {
        controller.fitCanvasToAspect(16 / 9);
        controller.fitCanvasToAspect(4 / 3);
        controller.fitCanvasToAspect(16 / 10);
      }

      expect(controller.floor.canvasWidth, closeTo(width, 2));
      expect(controller.floor.canvasHeight, closeTo(height, 2));
    });

    test('an empty floor keeps its height exactly', () {
      const empty = RestaurantTableLayout(
        id: 'empty',
        zones: [
          RestaurantZone(
            id: 'z1',
            name: 'Floor',
            legacyFloor: 'first',
            displayOrder: 1,
            renderMode: TableLayoutRenderMode.floorPlan,
            canvasWidth: 1440,
            canvasHeight: 900,
          ),
        ],
        tables: [],
      );
      final controller = _controllerFor(empty);

      controller.fitCanvasToAspect(16 / 9);
      expect(controller.floor.canvasHeight, 900);
      expect(controller.floor.canvasWidth, 1600);

      controller.fitCanvasToAspect(4 / 3);
      expect(controller.floor.canvasHeight, 900);
      expect(controller.floor.canvasWidth, 1200);

      controller.fitCanvasToAspect(16 / 10);
      expect(controller.floor.canvasHeight, 900);
      expect(controller.floor.canvasWidth, 1440);
    });

    test('a portrait canvas comes out landscape', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.fitCanvasToAspect(16 / 10);

      expect(
        controller.floor.canvasWidth,
        greaterThan(controller.floor.canvasHeight),
      );
    });

    test('no table ends up outside the canvas after fitting', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.fitCanvasToAspect(16 / 9);

      final floor = controller.floor;
      for (final object in floor.objects) {
        expect(object.boundingBox.right, lessThanOrEqualTo(floor.canvasWidth));
        expect(
          object.boundingBox.bottom,
          lessThanOrEqualTo(floor.canvasHeight),
        );
      }
    });

    test('fitting is one undoable step and marks the document dirty', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      final before = controller.floor.canvasWidth;

      controller.fitCanvasToAspect(16 / 10);
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.floor.canvasWidth, closeTo(before, 0.01));
    });

    test('fitting an already-correct canvas changes nothing', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.fitCanvasToAspect(16 / 10);
      final width = controller.floor.canvasWidth;
      final undoDepthMarker = controller.canUndo;

      controller.fitCanvasToAspect(16 / 10);

      expect(controller.floor.canvasWidth, width);
      expect(controller.canUndo, undoDepthMarker);
    });

    test('the fitted canvas survives a save/reload round trip', () {
      final controller = _controllerFor(
        RestaurantTableLayouts.floorPlanPreview,
      );
      controller.fitCanvasToAspect(16 / 10);
      final expected = controller.floor.canvasWidth;

      final reopened = EditorDocument.fromLayout(controller.toLayout());
      expect(
        reopened.floorById(controller.activeFloorId)!.canvasWidth,
        closeTo(expected, 0.01),
      );
    });
  });
}
