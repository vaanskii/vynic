import { SVG_SCALE } from '../constants';
import type { SvgBBox } from '../types';

export interface SvgPoint {
  x: number;
  y: number;
}

/** SVG-space delta from floor 1 coordinates to floor 2 coordinates */
export function anchorDelta(floor1Anchor: SvgPoint, floor2Anchor: SvgPoint): SvgPoint {
  return {
    x: floor2Anchor.x - floor1Anchor.x,
    y: floor2Anchor.y - floor1Anchor.y,
  };
}

/**
 * World-space group offset for floor 1 ghost geometry when the active viewBox is floor 2's.
 * Floor 1 bbox values are passed through floor 2's `svgPointToWorld` plus this offset.
 */
export function computeFloorGhostOffset(floor1Anchor: SvgPoint, floor2Anchor: SvgPoint): [number, number, number] {
  const delta = anchorDelta(floor1Anchor, floor2Anchor);
  return [delta.x * SVG_SCALE, 0, delta.y * SVG_SCALE];
}

/**
 * World-space group offset for floor 2 ghost geometry when the active viewBox is floor 1's.
 * Floor 2 bbox values are passed through floor 1's `svgPointToWorld` plus this offset.
 */
export function computeFloor2GhostOffset(floor1Anchor: SvgPoint, floor2Anchor: SvgPoint): [number, number, number] {
  return computeFloorGhostOffset(floor2Anchor, floor1Anchor);
}

/** Map a floor 2 bbox into floor 1 SVG coordinates using paired align anchors */
export function shiftBBoxToFloor1Space(bbox: SvgBBox, delta: SvgPoint): SvgBBox {
  return {
    x: bbox.x - delta.x,
    y: bbox.y - delta.y,
    width: bbox.width,
    height: bbox.height,
  };
}
