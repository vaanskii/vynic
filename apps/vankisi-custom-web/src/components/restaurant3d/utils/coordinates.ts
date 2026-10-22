import { DEFAULT_VIEWBOX, SVG_SCALE } from '../constants';
import type { SvgBBox } from '../types';

let viewBoxWidth: number = DEFAULT_VIEWBOX.width;
let viewBoxHeight: number = DEFAULT_VIEWBOX.height;

export function setViewBox(width: number, height: number): void {
  viewBoxWidth = width;
  viewBoxHeight = height;
}

export function getViewBox(): { width: number; height: number } {
  return { width: viewBoxWidth, height: viewBoxHeight };
}

export function svgPointToWorld(svgX: number, svgY: number): [number, number, number] {
  const x = (svgX - viewBoxWidth / 2) * SVG_SCALE;
  const z = (svgY - viewBoxHeight / 2) * SVG_SCALE;
  return [x, 0, z];
}

export function svgBBoxCenterToWorld(bbox: SvgBBox): [number, number, number] {
  return svgPointToWorld(bbox.x + bbox.width / 2, bbox.y + bbox.height / 2);
}

export function svgSizeToWorld(size: number): number {
  return size * SVG_SCALE;
}

export function svgBBoxToWorldSize(bbox: SvgBBox): { width: number; depth: number } {
  return {
    width: svgSizeToWorld(bbox.width),
    depth: svgSizeToWorld(bbox.height),
  };
}
