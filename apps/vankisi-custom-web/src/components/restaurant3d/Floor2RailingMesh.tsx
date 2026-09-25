import { useMemo } from 'react';
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import {
  FEATURE_BASE_Y,
  FLOOR1_Y,
  FLOOR2_ELEVATION,
  FLOOR2_Y,
  RAILING_HEIGHT,
} from './constants';
import { layerMaterial, type FloorLayerId } from './materials/ghostMaterials';
import { mats } from './materials/sharedMaterials';
import type { RailingSegment } from './types';
import { svgPointToWorld } from './utils/coordinates';

/** Thick enough to read from the default camera (~10 m away) */
const RAIL_RADIUS = 0.034;
const POST_RADIUS = 0.038;
const HANDRAIL_Y = FEATURE_BASE_Y + RAILING_HEIGHT;
const HANDRAIL_WORLD_Y = FLOOR2_ELEVATION + HANDRAIL_Y;
const STAIR_LIP_Y = FEATURE_BASE_Y + RAILING_HEIGHT * 0.38;
const POST_BASE_Y = FEATURE_BASE_Y + 0.02;
const STAIR_LIP_OFFSET = RAILING_HEIGHT * 0.38;
const RAIL_POST_DROP = HANDRAIL_Y - POST_BASE_Y;

/** North / south stair-lip paths in floor2.svg (plan Y) */
const STAIR_LIP_NORTH_Y = 538;
const STAIR_LIP_SOUTH_Y = 627;

interface Floor2RailingMeshProps {
  segments: RailingSegment[];
  layer?: FloorLayerId;
}

function worldXZ(svgX: number, svgY: number): [number, number] {
  const [x, , z] = svgPointToWorld(svgX, svgY);
  return [x, z];
}

function stairLipWorldY(svgY: number): number {
  const t = Math.max(
    0,
    Math.min(1, (svgY - STAIR_LIP_NORTH_Y) / (STAIR_LIP_SOUTH_Y - STAIR_LIP_NORTH_Y)),
  );
  // Smaller SVG Y = north / floor-2 landing; larger Y = south / floor-1 bottom
  const floorY = FLOOR2_Y + t * (FLOOR1_Y - FLOOR2_Y);
  return floorY + STAIR_LIP_OFFSET;
}

function connectorRelativeY(svgY: number, minY: number, maxY: number): number {
  const span = maxY - minY;
  const t = span > 0 ? (svgY - minY) / span : 0;
  return HANDRAIL_Y * (1 - t) + STAIR_LIP_Y * t;
}

function connectorWorldY(svgY: number, minY: number, maxY: number): number {
  const span = maxY - minY;
  const t = span > 0 ? (svgY - minY) / span : 0;
  return HANDRAIL_WORLD_Y * (1 - t) + stairLipWorldY(maxY) * t;
}

function connectorBounds(segment: RailingSegment): { minY: number; maxY: number } {
  const ys = segment.points.map(([, y]) => y);
  return { minY: Math.min(...ys), maxY: Math.max(...ys) };
}

/** Plan Y of the floor-2 balcony handrail (top of `rail4`) */
const CONNECTOR_TOP_Y = 435;

function connectorEndpointY(svgY: number, segment: RailingSegment): number {
  const midY = (STAIR_LIP_NORTH_Y + CONNECTOR_TOP_Y) / 2;
  if (segment.space === 'world') {
    return svgY >= midY ? stairLipWorldY(svgY) : HANDRAIL_WORLD_Y;
  }
  return svgY >= midY ? STAIR_LIP_Y : HANDRAIL_Y;
}

const STAIR_BOTTOM_RAIL_Y = FLOOR1_Y + STAIR_LIP_OFFSET - FLOOR2_ELEVATION;
/** Floor-1 walk height inside the elevated floor-2 group */
const FLOOR1_WALK_RELATIVE_Y = FLOOR1_Y - FLOOR2_ELEVATION;

function slopeXRangeOf(segment: RailingSegment): { minX: number; maxX: number } {
  return segment.slopeXRange ?? segmentXBounds(segment);
}

function slopeT(segment: RailingSegment, svgX: number): number {
  const { minX, maxX } = slopeXRangeOf(segment);
  return maxX > minX ? (svgX - minX) / (maxX - minX) : 1;
}

/** West end = floor-1 stair lip, east end = handrail (balcony join). */
function slopeFromStairBottomRailY(segment: RailingSegment, svgX: number): number {
  const t = slopeT(segment, svgX);
  return STAIR_BOTTOM_RAIL_Y * (1 - t) + HANDRAIL_Y * t;
}

/** Post foot follows stair: floor 1 at west → floor 2 slab at east. */
function slopeFromStairBottomPostBaseY(segment: RailingSegment, svgX: number): number {
  const t = slopeT(segment, svgX);
  return FLOOR1_WALK_RELATIVE_Y * (1 - t) + POST_BASE_Y * t;
}

function segmentXBounds(segment: RailingSegment): { minX: number; maxX: number } {
  const xs = segment.points.map(([x]) => x);
  return { minX: Math.min(...xs), maxX: Math.max(...xs) };
}

function pointRailY(segment: RailingSegment, svgX: number, svgY: number): number {
  if (segment.slopeFromStairBottom) {
    return slopeFromStairBottomRailY(segment, svgX);
  }
  if (segment.variant === 'connector') {
    const { minY, maxY } = connectorBounds(segment);
    if (maxY - minY < 1) {
      return connectorEndpointY(svgY, segment);
    }
    return segment.space === 'world'
      ? connectorWorldY(svgY, minY, maxY)
      : connectorRelativeY(svgY, minY, maxY);
  }
  return segmentRailY(segment);
}

function segmentRailY(segment: RailingSegment): number {
  if (segment.space === 'world' && segment.variant === 'stair-lip') {
    const avgY = segment.points.reduce((sum, [, y]) => sum + y, 0) / segment.points.length;
    return stairLipWorldY(avgY);
  }
  if (segment.variant === 'connector') {
    const { minY, maxY } = connectorBounds(segment);
    return segment.space === 'world'
      ? connectorWorldY((minY + maxY) / 2, minY, maxY)
      : connectorRelativeY((minY + maxY) / 2, minY, maxY);
  }
  return segment.variant === 'stair-lip' ? STAIR_LIP_Y : HANDRAIL_Y;
}

function segmentPostBaseY(segment: RailingSegment, svgX?: number, svgY?: number): number {
  if (segment.space === 'world') {
    const railY =
      svgX !== undefined && svgY !== undefined
        ? pointRailY(segment, svgX, svgY)
        : segmentRailY(segment);
    return railY - RAIL_POST_DROP;
  }
  if (segment.slopeFromStairBottom && svgX !== undefined) {
    return slopeFromStairBottomPostBaseY(segment, svgX);
  }
  return POST_BASE_Y;
}

function planRailSegment(
  ax: number,
  ay: number,
  bx: number,
  by: number,
  heightY: number,
): THREE.BufferGeometry | null {
  const [x0, z0] = worldXZ(ax, ay);
  const [x1, z1] = worldXZ(bx, by);
  const dx = x1 - x0;
  const dz = z1 - z0;
  const len = Math.hypot(dx, dz);
  if (len < 0.004) return null;

  const geo = new THREE.CylinderGeometry(RAIL_RADIUS, RAIL_RADIUS, len, 8, 1, false);
  const angle = Math.atan2(dx, dz);
  const matrix = new THREE.Matrix4()
    .makeRotationX(Math.PI / 2)
    .multiply(new THREE.Matrix4().makeRotationY(angle))
    .multiply(new THREE.Matrix4().makeTranslation((x0 + x1) / 2, heightY, (z0 + z1) / 2));
  geo.applyMatrix4(matrix);
  return geo;
}

function smoothRailTube(
  points: [number, number][],
  yAtPoint: (svgX: number, svgY: number) => number,
): THREE.BufferGeometry | null {
  const curvePoints = points.map(([sx, sy]) => {
    const [x, , z] = svgPointToWorld(sx, sy);
    return new THREE.Vector3(x, yAtPoint(sx, sy), z);
  });
  if (curvePoints.length < 2) return null;

  const curve = new THREE.CatmullRomCurve3(curvePoints, false, 'catmullrom', 0.22);
  const length = curve.getLength();
  const tubularSegments = Math.max(16, Math.ceil(length / 0.04));
  return new THREE.TubeGeometry(curve, tubularSegments, RAIL_RADIUS, 10, false);
}

function slopedRailSegment(
  ax: number,
  ay: number,
  bx: number,
  by: number,
  y0: number,
  y1: number,
): THREE.BufferGeometry | null {
  const [x0, z0] = worldXZ(ax, ay);
  const [x1, z1] = worldXZ(bx, by);
  const dx = x1 - x0;
  const dy = y1 - y0;
  const dz = z1 - z0;
  const len = Math.hypot(dx, dy, dz);
  if (len < 0.004) return null;

  const geo = new THREE.CylinderGeometry(RAIL_RADIUS, RAIL_RADIUS, len, 8, 1, false);
  const direction = new THREE.Vector3(dx, dy, dz).normalize();
  const up = new THREE.Vector3(0, 1, 0);
  const quaternion = new THREE.Quaternion().setFromUnitVectors(up, direction);
  const matrix = new THREE.Matrix4()
    .makeRotationFromQuaternion(quaternion)
    .multiply(
      new THREE.Matrix4().makeTranslation((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
    );
  geo.applyMatrix4(matrix);
  return geo;
}

function cornerPost(
  svgX: number,
  svgY: number,
  heightY: number,
  baseY: number,
): THREE.BufferGeometry {
  const [x, , z] = svgPointToWorld(svgX, svgY);
  const postHeight = heightY - baseY;
  const geo = new THREE.CylinderGeometry(POST_RADIUS, POST_RADIUS, postHeight, 10);
  const matrix = new THREE.Matrix4().makeTranslation(x, baseY + postHeight / 2, z);
  geo.applyMatrix4(matrix);
  return geo;
}

export function Floor2RailingMesh({ segments, layer }: Floor2RailingMeshProps) {
  const geometry = useMemo(() => {
    const parts: THREE.BufferGeometry[] = [];

    for (const segment of segments) {
      const pts = segment.points;
      if (!pts.length) continue;

      const usesPointY = segment.variant === 'connector' || segment.slopeFromStairBottom;

      if (segment.kind === 'post') {
        const [px, py] = pts[0];
        const heightY = pointRailY(segment, px, py);
        const baseY = segmentPostBaseY(segment, px, py);
        parts.push(cornerPost(px, py, heightY, baseY));
        continue;
      }

      if (segment.smooth && pts.length >= 2) {
        const yAtPoint = (svgX: number, svgY: number) => pointRailY(segment, svgX, svgY);
        const tube = smoothRailTube(pts, yAtPoint);
        if (tube) parts.push(tube);
        continue;
      }

      for (let i = 0; i < pts.length - 1; i += 1) {
        const [ax, ay] = pts[i];
        const [bx, by] = pts[i + 1];
        if (usesPointY) {
          const seg = slopedRailSegment(
            ax,
            ay,
            bx,
            by,
            pointRailY(segment, ax, ay),
            pointRailY(segment, bx, by),
          );
          if (seg) parts.push(seg);
          continue;
        }
        const seg = planRailSegment(ax, ay, bx, by, segmentRailY(segment));
        if (seg) parts.push(seg);
      }
    }

    if (!parts.length) return null;
    const merged = mergeGeometries(parts, false);
    parts.forEach((g) => g.dispose());
    if (!merged) return null;
    merged.computeBoundingSphere();
    return merged;
  }, [segments]);

  const material = useMemo(() => {
    const styled = mats.railing().clone();
    styled.color.set('#b8b0a6');
    styled.emissive.set('#5a5248');
    styled.emissiveIntensity = 0.12;
    styled.metalness = 0.55;
    styled.roughness = 0.32;
    return layer ? layerMaterial(styled, layer, 'geometry') : styled;
  }, [layer]);

  if (!geometry) return null;

  return (
    <mesh
      geometry={geometry}
      material={material}
      renderOrder={25}
      raycast={() => null}
    />
  );
}
