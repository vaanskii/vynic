import type { FloorId, FloorPlanData, SvgBBox } from '../types';
import { FLOOR2_ELEVATION } from '../constants';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize, svgPointToWorld } from './coordinates';
import { mergeBboxes } from './pathBounds';

export interface DefaultCameraView {
  position: [number, number, number];
  target: [number, number, number];
  fov: number;
  /** Screen-up direction for locked top-down views (XZ plane) */
  up?: [number, number, number];
}

export interface TopDownCameraView {
  target: [number, number, number];
  distance: number;
}

/** SVG wall groups that frame the public entrance on each floor */
const MOBILE_ENTRANCE_WALLS: Record<FloorId, readonly [string, string]> = {
  floor1: ['wall12', 'wall1'],
  /** Floor 2: same pairing pattern — south sill + east jamb at the stair landing */
  floor2: ['wall4', 'wall1'],
};

/** Furthest orbit distance — also used to lock zoom */
const ORBIT_DISTANCE_FACTOR = { mobile: 2.40, desktop: 1.8 } as const;

/** Extra pull-back when in bird's-eye mode so the full slab fits */
const TOP_DOWN_DISTANCE_FACTOR = { mobile: 1.14, desktop: 1.45 } as const;

/** Polar angle below this = bird's-eye / plan view (radians from vertical) */
export const TOP_DOWN_POLAR_THRESHOLD = 0.2;

export function getOrbitDistance(sceneWidth: number, mobile = false): number {
  return sceneWidth * (mobile ? ORBIT_DISTANCE_FACTOR.mobile : ORBIT_DISTANCE_FACTOR.desktop);
}

export function isTopDownPolarAngle(polarAngle: number): boolean {
  return polarAngle < TOP_DOWN_POLAR_THRESHOLD;
}

function mergeWallGroupBBox(floorPlan: FloorPlanData, wallGroup: string): SvgBBox | null {
  const boxes = floorPlan.zones
    .filter(
      (zone) =>
        (zone.kind === 'wall' || zone.kind === 'structure') &&
        zone.id.startsWith(`${wallGroup}-`),
    )
    .map((zone) => zone.bbox);

  return mergeBboxes(boxes);
}

/** Corner where the entrance jamb walls meet (thin axis from each wall) */
function entranceCornerFromWalls(wallA: SvgBBox, wallB: SvgBBox): [number, number] {
  const aVertical = wallA.width < wallA.height;
  const bVertical = wallB.width < wallB.height;

  if (aVertical && !bVertical) {
    return [wallA.x + wallA.width / 2, wallB.y + wallB.height / 2];
  }
  if (!aVertical && bVertical) {
    return [wallB.x + wallB.width / 2, wallA.y + wallA.height / 2];
  }

  return [
    (wallA.x + wallA.width / 2 + wallB.x + wallB.width / 2) / 2,
    (wallA.y + wallA.height / 2 + wallB.y + wallB.height / 2) / 2,
  ];
}

function entranceUpVector(
  floorPlan: FloorPlanData,
  entranceSvgX: number,
  entranceSvgY: number,
): [number, number, number] {
  const [cx, , cz] = svgBBoxCenterToWorld(floorPlan.boundary);
  const [ex, , ez] = svgPointToWorld(entranceSvgX, entranceSvgY);
  const inX = cx - ex;
  const inZ = cz - ez;
  const len = Math.hypot(inX, inZ) || 1;
  return [inX / len, 0, inZ / len];
}

/** Rotate a flat (XZ) unit vector around world Y — negative = clockwise on screen */
function rotateXZYaw([x, , z]: [number, number, number], radians: number): [number, number, number] {
  const c = Math.cos(radians);
  const s = Math.sin(radians);
  return [x * c - z * s, 0, x * s + z * c];
}

/** Fine-tune mobile plan rotation per floor (radians, clockwise on screen when negative) */
const MOBILE_ENTRANCE_YAW_TRIM: Record<FloorId, number> = {
  floor1: 0.32,
  floor2: 2.19,
};

/** Extra pull-back for locked mobile top-down only */
const MOBILE_TOP_DOWN_PULLBACK = 1.22;

/** Center on floor boundary and pull back enough to frame the whole plan */
export function getTopDownView(
  floorPlan: FloorPlanData,
  sceneWidth: number,
  mobile = false, 
  fovDeg = 42,
): TopDownCameraView {
  const { boundary } = floorPlan;
  const [cx, , cz] = svgBBoxCenterToWorld(boundary);
  const { width, depth } = svgBBoxToWorldSize(boundary);
  const span = Math.max(width, depth);
  const fovRad = (fovDeg * Math.PI) / 180;
  const fitPadding = mobile ? 1.4 : 1.28;
  const fitDistance = (span / 2 / Math.tan(fovRad / 2)) * fitPadding;
  const baseDistance = getOrbitDistance(sceneWidth, mobile);
  const boost = mobile ? TOP_DOWN_DISTANCE_FACTOR.mobile : TOP_DOWN_DISTANCE_FACTOR.desktop;
  const distance = Math.max(fitDistance, baseDistance * boost);

  const targetY = floorPlan.floorId === 'floor2' ? FLOOR2_ELEVATION * 0.55 : 0;

  return {
    target: [cx, targetY, cz],
    distance,
  };
}

/**
 * Mobile: locked bird's-eye, rotated so the entrance (wall12 + wall1 on floor 1) sits at
 * the bottom of the screen and the dining room opens toward the top.
 */
export function getMobileTopDownEntranceCamera(
  floorPlan: FloorPlanData,
  sceneWidth: number,
): DefaultCameraView {
  const fov = 48;
  const { target, distance: baseDistance } = getTopDownView(floorPlan, sceneWidth, true, fov);
  const distance = baseDistance * MOBILE_TOP_DOWN_PULLBACK;
  const [wallAId, wallBId] = MOBILE_ENTRANCE_WALLS[floorPlan.floorId];
  const wallA = mergeWallGroupBBox(floorPlan, wallAId);
  const wallB = mergeWallGroupBBox(floorPlan, wallBId);

  let up: [number, number, number] = [0, 0, -1];
  if (wallA && wallB) {
    const [entranceSvgX, entranceSvgY] = entranceCornerFromWalls(wallA, wallB);
    up = entranceUpVector(floorPlan, entranceSvgX, entranceSvgY);
  }
  up = rotateXZYaw(up, MOBILE_ENTRANCE_YAW_TRIM[floorPlan.floorId]);

  return {
    position: [target[0], target[1] + distance, target[2]],
    target,
    fov,
    up,
  };
}

/** Shift a camera view when floor 2 geometry is grouped with an X/Z align offset */
export function offsetCameraXZ(
  view: DefaultCameraView,
  offset: [number, number, number],
): DefaultCameraView {
  return {
    ...view,
    position: [view.position[0] + offset[0], view.position[1], view.position[2] + offset[2]],
    target: [view.target[0] + offset[0], view.target[1], view.target[2] + offset[2]],
  };
}

export function getViewPolarAngle(view: DefaultCameraView): number {
  const dx = view.position[0] - view.target[0];
  const dy = view.position[1] - view.target[1];
  const dz = view.position[2] - view.target[2];
  return Math.atan2(Math.hypot(dx, dz), dy);
}

/**
 * Starting view: centered on the floor, pulled back to fit the full plan.
 */
export function getEntranceOverviewCamera(
  floorPlan: FloorPlanData,
  sceneWidth: number,
  mobile = false,
): DefaultCameraView {
  const fov = mobile ? 46 : 42;
  const { target, distance } = getTopDownView(floorPlan, sceneWidth, mobile, fov);
  const polar = mobile ? 0.96 : 0.92;
  /** South-west oblique — same orbit center and distance as top-down */
  const azimuth = Math.PI * 1.08;

  const position: [number, number, number] = [
    target[0] + distance * Math.sin(polar) * Math.cos(azimuth),
    target[1] + distance * Math.cos(polar),
    target[2] + distance * Math.sin(polar) * Math.sin(azimuth),
  ];

  return {
    position,
    target,
    fov,
  };
}

/**
 * Floor 2: overview from the stair landing, looking across the VIP floor.
 */
export function getFloor2OverviewCamera(
  floorPlan: FloorPlanData,
  sceneWidth: number,
  mobile = false,
): DefaultCameraView {
  const stairSteps = floorPlan.zones.filter((z) => z.kind === 'stair-step');
  const stairsBBox = mergeBboxes(stairSteps.map((z) => z.bbox));
  const boundary = floorPlan.boundary;

  let targetX = sceneWidth * 0.15;
  let targetZ = sceneWidth * 0.12;

  if (stairsBBox) {
    [targetX, , targetZ] = svgBBoxCenterToWorld(stairsBBox);
  } else if (boundary) {
    [targetX, , targetZ] = svgBBoxCenterToWorld(boundary);
  }

  const target: [number, number, number] = [targetX, FLOOR2_ELEVATION * 0.62, targetZ];
  const distance = getOrbitDistance(sceneWidth, mobile);
  const polar = mobile ? 1.02 : 0.98;
  const azimuth = Math.PI * 0.52;

  const position: [number, number, number] = [
    target[0] + distance * Math.sin(polar) * Math.cos(azimuth),
    FLOOR2_ELEVATION + distance * Math.cos(polar) * 0.85,
    target[2] + distance * Math.sin(polar) * Math.sin(azimuth),
  ];

  return {
    position,
    target,
    fov: mobile ? 46 : 42,
  };
}

export function getOverviewCamera(
  floorPlan: FloorPlanData,
  sceneWidth: number,
  mobile = false,
): DefaultCameraView {
  if (floorPlan.floorId === 'floor2') {
    return getFloor2OverviewCamera(floorPlan, sceneWidth, mobile);
  }
  return getEntranceOverviewCamera(floorPlan, sceneWidth, mobile);
}
