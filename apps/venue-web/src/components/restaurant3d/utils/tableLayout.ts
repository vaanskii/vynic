import type { SvgTable } from '../types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './coordinates';
import { mergeBboxes } from './pathBounds';

export interface ChairSlot {
  localX: number;
  localZ: number;
}

export interface TableLayout {
  centerX: number;
  centerZ: number;
  chairs: ChairSlot[];
  ringInner: number;
  ringOuter: number;
}

export const SEAT_ORBIT_RADIUS = 0.045;
const SEAT_OUTSET = 0.11;
const RING_PADDING = 0.028;

function getSurfaces(table: SvgTable) {
  return table.surfaces.length > 0 ? table.surfaces : [{ shape: 'box' as const, bbox: table.bbox }];
}

export function computeTableLayout(table: SvgTable): TableLayout {
  const surfaces = getSurfaces(table);
  const surfaceBounds = mergeBboxes(surfaces.map((surface) => surface.bbox));
  const anchor = surfaceBounds ?? table.bbox;
  const [cx, , cz] = svgBBoxCenterToWorld(anchor);
  const chairs: ChairSlot[] = [];

  if (table.chairs.length) {
    for (const chair of table.chairs) {
      const [x, , z] = svgBBoxCenterToWorld(chair);
      chairs.push({ localX: x - cx, localZ: z - cz });
    }
  } else {
    for (const surface of getSurfaces(table)) {
      const [sx, , sz] = svgBBoxCenterToWorld(surface.bbox);
      const { width, depth } = svgBBoxToWorldSize(surface.bbox);
      const w = Math.max(width, 0.08);
      const d = Math.max(depth, 0.08);
      const lx = sx - cx;
      const lz = sz - cz;

      if (surface.shape === 'cylinder') {
        const orbit = Math.max(Math.min(w, d) / 2, 0.06) + SEAT_OUTSET;
        for (let i = 0; i < 4; i += 1) {
          const angle = (i / 4) * Math.PI * 2;
          chairs.push({
            localX: lx + Math.cos(angle) * orbit,
            localZ: lz + Math.sin(angle) * orbit,
          });
        }
      } else {
        chairs.push({ localX: lx, localZ: lz - d / 2 - SEAT_OUTSET });
        chairs.push({ localX: lx, localZ: lz + d / 2 + SEAT_OUTSET });
        chairs.push({ localX: lx - w / 2 - SEAT_OUTSET, localZ: lz });
        chairs.push({ localX: lx + w / 2 + SEAT_OUTSET, localZ: lz });
      }
    }
  }

  let maxReach = 0.1;
  for (const chair of chairs) {
    maxReach = Math.max(maxReach, Math.hypot(chair.localX, chair.localZ) + SEAT_ORBIT_RADIUS);
  }

  for (const surface of getSurfaces(table)) {
    const [sx, , sz] = svgBBoxCenterToWorld(surface.bbox);
    const { width, depth } = svgBBoxToWorldSize(surface.bbox);
    const hw = Math.max(width, 0.08) / 2;
    const hd = Math.max(depth, 0.08) / 2;
    const lx = sx - cx;
    const lz = sz - cz;
    maxReach = Math.max(
      maxReach,
      Math.hypot(lx + hw, lz + hd),
      Math.hypot(lx - hw, lz + hd),
      Math.hypot(lx + hw, lz - hd),
      Math.hypot(lx - hw, lz - hd),
    );
  }

  const ringOuter = maxReach + RING_PADDING;
  const ringInner = ringOuter * 0.88;

  return { centerX: cx, centerZ: cz, chairs, ringInner, ringOuter };
}
