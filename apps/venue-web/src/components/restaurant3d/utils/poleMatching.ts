import { FLOOR2_FLOOR1_POLE_PAIRS, SVG_SCALE } from '../constants';
import type { FloorZone } from '../types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './coordinates';

/** Max XZ distance (world units) for automatic floor 1 / floor 2 pole pairing */
const POLE_MATCH_RADIUS_WORLD = 0.45;

export interface PoleInstance {
  x: number;
  z: number;
  radius: number;
}

export interface PoleConnection {
  floor1Id: string;
  floor2Id: string;
  x: number;
  z: number;
  radius: number;
}

function poleInstanceFromZone(zone: FloorZone): PoleInstance {
  const { width, depth } = svgBBoxToWorldSize(zone.bbox);
  const [x, , z] = svgBBoxCenterToWorld(zone.bbox);
  const radius = Math.max(Math.min(width, depth) / 2, 0.05);
  return { x, z, radius };
}

function poleInstanceFromFloor1Zone(
  zone: FloorZone,
  offset: [number, number, number],
): PoleInstance {
  const base = poleInstanceFromZone(zone);
  return {
    x: base.x + offset[0],
    z: base.z + offset[2],
    radius: base.radius,
  };
}

function poleInstanceFromFloor2Zone(
  zone: FloorZone,
  offset: [number, number, number],
): PoleInstance {
  const base = poleInstanceFromZone(zone);
  return {
    x: base.x + offset[0],
    z: base.z + offset[2],
    radius: base.radius,
  };
}

function connectionFromPair(
  floor1Zone: FloorZone,
  floor2Zone: FloorZone,
  floor1Offset: [number, number, number],
  floor2Offset: [number, number, number],
): PoleConnection {
  const floor2Inst = poleInstanceFromFloor2Zone(floor2Zone, floor2Offset);
  const floor1Inst = poleInstanceFromFloor1Zone(floor1Zone, floor1Offset);
  return {
    floor1Id: floor1Zone.id,
    floor2Id: floor2Zone.id,
    x: floor2Inst.x,
    z: floor2Inst.z,
    radius: Math.max(floor1Inst.radius, floor2Inst.radius),
  };
}

/**
 * Pair floor 1 and floor 2 poles into shared columns.
 * Pass world XZ offsets for whichever floor is drawn in an aligned ghost group.
 */
export function matchPoleColumns(
  floor1Poles: FloorZone[],
  floor2Poles: FloorZone[],
  floor1Offset: [number, number, number] = [0, 0, 0],
  floor2Offset: [number, number, number] = [0, 0, 0],
): PoleConnection[] {
  if (!floor1Poles.length || !floor2Poles.length) return [];

  const floor1ById = new Map(floor1Poles.map((zone) => [zone.id, zone]));
  const floor2ById = new Map(floor2Poles.map((zone) => [zone.id, zone]));

  const usedF1 = new Set<string>();
  const usedF2 = new Set<string>();
  const connections: PoleConnection[] = [];

  for (const [floor2Id, floor1Id] of Object.entries(FLOOR2_FLOOR1_POLE_PAIRS)) {
    const floor2Zone = floor2ById.get(floor2Id);
    const floor1Zone = floor1ById.get(floor1Id);
    if (!floor2Zone || !floor1Zone) continue;

    connections.push(connectionFromPair(floor1Zone, floor2Zone, floor1Offset, floor2Offset));
    usedF1.add(floor1Id);
    usedF2.add(floor2Id);
  }

  const f1 = floor1Poles
    .filter((zone) => !usedF1.has(zone.id))
    .map((zone) => ({
      zone,
      inst: poleInstanceFromFloor1Zone(zone, floor1Offset),
    }));
  const f2 = floor2Poles
    .filter((zone) => !usedF2.has(zone.id))
    .map((zone) => ({
      zone,
      inst: poleInstanceFromFloor2Zone(zone, floor2Offset),
    }));

  for (const floor2 of f2) {
    let best: { zone: FloorZone; inst: PoleInstance; dist: number } | null = null;

    for (const floor1 of f1) {
      if (usedF1.has(floor1.zone.id)) continue;
      const dist = Math.hypot(floor1.inst.x - floor2.inst.x, floor1.inst.z - floor2.inst.z);
      if (dist > POLE_MATCH_RADIUS_WORLD) continue;
      if (!best || dist < best.dist) {
        best = { zone: floor1.zone, inst: floor1.inst, dist };
      }
    }

    if (!best) continue;

    usedF1.add(best.zone.id);
    connections.push({
      floor1Id: best.zone.id,
      floor2Id: floor2.zone.id,
      x: floor2.inst.x,
      z: floor2.inst.z,
      radius: Math.max(best.inst.radius, floor2.inst.radius),
    });
  }

  return connections;
}

/** SVG-space footprint radius for debug / future pole-align dots */
export function poleMatchThresholdSvg(): number {
  return POLE_MATCH_RADIUS_WORLD / SVG_SCALE;
}
