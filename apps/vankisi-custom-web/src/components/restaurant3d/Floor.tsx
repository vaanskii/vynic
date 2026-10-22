import { useMemo } from 'react';
import { Shape } from 'three';
import { FLOOR_Y, SVG_SCALE } from './constants';
import { layerMaterial, type FloorLayerId } from './materials/ghostMaterials';
import { mats } from './materials/sharedMaterials';
import type { FloorId, FloorSlab, SvgBBox } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize, svgPointToWorld } from './utils/coordinates';
import { parsePathPolyline } from './utils/svgPathPoints';

const FLOOR_PADDING_SCALE = 1.32;
/** Extra cutout margin around the stair run (SVG units) */
const STAIR_OPENING_PAD_SVG = 14;

interface FloorProps {
  boundary: SvgBBox;
  floorId?: FloorId;
  stairOpening?: SvgBBox;
  /** Floor regions from floor-bg (SVG coordinates) */
  floorSlabs?: FloorSlab[];
  layer: FloorLayerId;
}

interface FloorPanel {
  key: string;
  cx: number;
  cz: number;
  w: number;
  d: number;
}

function expandOpening(opening: SvgBBox): SvgBBox {
  const pad = STAIR_OPENING_PAD_SVG;
  return {
    x: opening.x - pad,
    y: opening.y - pad,
    width: opening.width + pad * 2,
    height: opening.height + pad * 2,
  };
}

function openingsOverlapSlab(slab: SvgBBox, opening: SvgBBox): boolean {
  return (
    slab.x < opening.x + opening.width &&
    slab.x + slab.width > opening.x &&
    slab.y < opening.y + opening.height &&
    slab.y + slab.height > opening.y
  );
}

function shapeFromSvgPath(d: string): Shape {
  const points = parsePathPolyline(d, 32);
  const shape = new Shape();
  points.forEach(([sx, sy], i) => {
    const [wx, , wz] = svgPointToWorld(sx, sy);
    if (i === 0) shape.moveTo(wx, -wz);
    else shape.lineTo(wx, -wz);
  });
  shape.closePath();
  return shape;
}

/**
 * Build floor panels for one slab, cutting a stair hole when it overlaps.
 */
function panelsForSlab(slab: SvgBBox, key: string, stairOpening?: SvgBBox): FloorPanel[] {
  const { width: slabW, depth: slabD } = svgBBoxToWorldSize(slab);
  const [cx, , cz] = svgBBoxCenterToWorld(slab);
  const hw = slabW / 2;
  const hd = slabD / 2;
  const minPanel = 0.03;

  if (!stairOpening || !openingsOverlapSlab(slab, expandOpening(stairOpening))) {
    return [{ key, cx, cz, w: slabW, d: slabD }];
  }

  const expanded = expandOpening(stairOpening);
  const [x0, , z0] = svgPointToWorld(expanded.x, expanded.y);
  const [x1, , z1] = svgPointToWorld(
    expanded.x + expanded.width,
    expanded.y + expanded.height,
  );

  const lx0 = Math.max(x0 - cx, -hw);
  const lx1 = Math.min(x1 - cx, hw);
  const lz0 = Math.max(z0 - cz, -hd);
  const lz1 = Math.min(z1 - cz, hd);

  const panels: FloorPanel[] = [];
  const holeD = lz1 - lz0;

  if (holeD < SVG_SCALE * 18) {
    return [{ key, cx, cz, w: slabW, d: slabD }];
  }

  const northD = lz0 - -hd;
  if (northD > minPanel) {
    panels.push({ key: `${key}-n`, cx, cz: cz + (-hd + lz0) / 2, w: slabW, d: northD });
  }

  const southD = hd - lz1;
  if (southD > minPanel) {
    panels.push({ key: `${key}-s`, cx, cz: cz + (lz1 + hd) / 2, w: slabW, d: southD });
  }

  const westW = lx0 - -hw;
  if (westW > minPanel) {
    panels.push({
      key: `${key}-w`,
      cx: cx + (-hw + lx0) / 2,
      cz: cz + (lz0 + lz1) / 2,
      w: westW,
      d: holeD,
    });
  }

  const eastW = hw - lx1;
  if (eastW > minPanel) {
    panels.push({
      key: `${key}-e`,
      cx: cx + (lx1 + hw) / 2,
      cz: cz + (lz0 + lz1) / 2,
      w: eastW,
      d: holeD,
    });
  }

  return panels.length ? panels : [{ key, cx, cz, w: slabW, d: slabD }];
}

export function Floor({ boundary, floorId = 'floor1', stairOpening, floorSlabs, layer }: FloorProps) {
  const isFloor2 = floorId === 'floor2';
  const hasSlabFloor = Boolean(floorSlabs?.length);
  const { width, depth } = svgBBoxToWorldSize(boundary);
  const floorW = width * (hasSlabFloor || isFloor2 ? 1 : FLOOR_PADDING_SCALE);
  const floorD = depth * (hasSlabFloor || isFloor2 ? 1 : FLOOR_PADDING_SCALE);
  const [x, , z] = svgPointToWorld(
    boundary.x + boundary.width / 2,
    boundary.y + boundary.height / 2,
  );

  const floorMat = useMemo(() => {
    const base = isFloor2 ? mats.floorSlabFloor2() : mats.floorSlab();
    return layerMaterial(base, layer, 'floor');
  }, [isFloor2, layer]);

  const pathShapes = useMemo(() => {
    if (!hasSlabFloor) return [];
    return floorSlabs!
      .filter((slab) => slab.pathD)
      .map((slab) => ({ key: slab.id, shape: shapeFromSvgPath(slab.pathD!) }));
  }, [hasSlabFloor, floorSlabs]);

  const panels = useMemo(() => {
    const cutoutForSlab = (slab: FloorSlab): SvgBBox | undefined => {
      if (!stairOpening) return undefined;
      if (isFloor2 && slab.id === 'Rectangle 5') return stairOpening;
      if (openingsOverlapSlab(slab.bbox, expandOpening(stairOpening))) return stairOpening;
      return undefined;
    };

    if (hasSlabFloor) {
      return floorSlabs!
        .filter((slab) => !slab.pathD)
        .flatMap((slab) => panelsForSlab(slab.bbox, slab.id, cutoutForSlab(slab)));
    }
    if (isFloor2 && stairOpening) {
      return panelsForSlab(
        { x: boundary.x, y: boundary.y, width: boundary.width, height: boundary.height },
        'boundary',
        stairOpening,
      );
    }
    if (!isFloor2 && stairOpening) {
      return panelsForSlab(
        { x: boundary.x, y: boundary.y, width: boundary.width, height: boundary.height },
        'floor1',
        stairOpening,
      );
    }
    return [{ key: 'floor1', cx: x, cz: z, w: floorW, d: floorD }];
  }, [hasSlabFloor, isFloor2, floorSlabs, stairOpening, boundary, x, z, floorW, floorD]);

  return (
    <group raycast={() => null}>
      {pathShapes.map(({ key, shape }) => (
        <mesh
          key={key}
          position={[0, FLOOR_Y - 0.003, 0]}
          rotation={[-Math.PI / 2, 0, 0]}
        >
          <shapeGeometry args={[shape]} />
          <primitive object={floorMat} attach="material" />
        </mesh>
      ))}
      {panels.map((panel) => (
        <mesh
          key={panel.key}
          position={[panel.cx, FLOOR_Y - 0.003, panel.cz]}
          rotation={[-Math.PI / 2, 0, 0]}
        >
          <planeGeometry args={[panel.w, panel.d]} />
          <primitive object={floorMat} attach="material" />
        </mesh>
      ))}
    </group>
  );
}
