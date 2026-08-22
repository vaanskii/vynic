import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vynic/apps/windows_pos/widgets/admin/shared/admin_design.dart';

import 'package:vynic/apps/windows_pos/widgets/floor_plan/floor_plan_seats.dart';
import 'package:vynic/core/models/table_layout.dart';
import 'package:vynic/core/ui/vynic_colors.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'floor_editor_model.dart';
import 'floor_editor_painter.dart';

/// Read-only look at how the floor will render on the operational Tables
/// screen.
///
/// Every table is drawn in its *free* state on purpose: the editor must not
/// depend on live table status, and inventing occupied/reserved tiles would
/// misrepresent the floor. This checks sizing, spacing and labels — not
/// operations.
class FloorEditorPreviewDialog extends StatelessWidget {
  const FloorEditorPreviewDialog({super.key, required this.floor});

  final EditorFloor floor;

  static Future<void> show(BuildContext context, EditorFloor floor) {
    return showDialog<void>(
      context: context,
      builder: (context) => FloorEditorPreviewDialog(floor: floor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: AdminDesign.panel,
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: math.min(1180, media.width - 56),
        height: math.min(820, media.height - 56),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AdminDesign.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 19,
                    color: AdminDesign.accentDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${floor.name} — POS გადახედვა',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AdminDesign.text,
                          ),
                        ),
                        const Text(
                          'ყველა მაგიდა ნაჩვენებია თავისუფალ მდგომარეობაში',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AdminDesign.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 19),
                    color: AdminDesign.muted,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: AdminDesign.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _PreviewSurface(floor: floor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.floor});

  final EditorFloor floor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same uniform (aspect-preserving) fit the POS floor plan uses, so
        // the preview does not flatter the layout.
        final scale = math
            .min(
              constraints.maxWidth / floor.canvasWidth,
              constraints.maxHeight / floor.canvasHeight,
            )
            .clamp(0.05, 3.0)
            .toDouble();
        final width = floor.canvasWidth * scale;
        final height = floor.canvasHeight * scale;

        // The painter handles the room itself (walls, bar, zones) *and* the
        // chairs, which the POS also draws; tables are real widgets so they
        // match the POS tile treatment exactly.
        final backdrop = floor.copyWith(
          objects: [
            for (final object in floor.objects)
              if (!object.isTable) object,
          ],
        );
        final seatLayer = floor.copyWith(
          objects: [
            for (final object in floor.objects)
              if (object.isTable) object,
          ],
        );

        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FloorEditorPainter(
                        floor: backdrop,
                        scale: scale,
                        offset: Offset.zero,
                        selection: const {},
                        gridVisible: false,
                        gridSize: 20,
                        guides: const [],
                        marquee: null,
                        segmentPreview: null,
                        segmentThickness: 16,
                        showHandles: false,
                        showSeats: false,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FloorPlanSeatsPainter(
                        tables: [
                          for (final table in seatLayer.tables)
                            (
                              rect: table.rect,
                              rotation: table.rotation,
                              shape: table.tableShape,
                              capacity: table.capacity,
                            ),
                        ],
                        scale: scale,
                        color: VynicFloorTokens.freeDot,
                      ),
                    ),
                  ),
                  for (final table in floor.tables)
                    _PreviewTable(table: table, scale: scale),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.table, required this.scale});

  final EditorObject table;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final width = table.width * scale;
    final height = table.height * scale;
    final left = table.x * scale;
    final top = table.y * scale;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: table.rotationRadians,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AdminDesign.border, width: 2),
            borderRadius: BorderRadius.circular(_radiusFor(table.tableShape)),
            boxShadow: [
              BoxShadow(
                color: AdminDesign.border.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.table_restaurant,
                    size: 20,
                    color: AdminDesign.text,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    table.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AdminDesign.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mirrors the POS floor plan's corner radii so the preview is faithful.
  static double _radiusFor(RestaurantTableShape shape) {
    switch (shape) {
      case RestaurantTableShape.circle:
        return 999;
      case RestaurantTableShape.rounded:
      case RestaurantTableShape.booth:
        return 22;
      case RestaurantTableShape.barSeat:
        return 14;
      case RestaurantTableShape.rectangle:
      case RestaurantTableShape.square:
      case RestaurantTableShape.long:
        return 8;
    }
  }
}
