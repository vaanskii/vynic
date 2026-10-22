import { useMemo } from 'react';
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { FEATURE_BASE_Y, GLASS_WALL_HEIGHT } from './constants';
import { layerMaterial, type FloorLayerId } from './materials/ghostMaterials';
import { mats } from './materials/sharedMaterials';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

interface GlassWallMeshProps {
  zones: FloorZone[];
  layer: FloorLayerId;
}

export function GlassWallMesh({ zones, layer }: GlassWallMeshProps) {
  const geometry = useMemo(() => {
    const parts: THREE.BufferGeometry[] = [];

    for (const zone of zones) {
      const { width, depth } = svgBBoxToWorldSize(zone.bbox);
      if (width < 0.004 && depth < 0.004) continue;

      const [x, , z] = svgBBoxCenterToWorld(zone.bbox);
      const isVertical = depth > width * 1.5;
      const w = isVertical ? Math.max(width, 0.025) : Math.max(width, 0.03);
      const d = isVertical ? Math.max(depth, 0.03) : Math.max(depth, 0.025);
      const geo = new THREE.BoxGeometry(w, GLASS_WALL_HEIGHT, d);
      geo.applyMatrix4(
        new THREE.Matrix4().makeTranslation(x, FEATURE_BASE_Y + GLASS_WALL_HEIGHT / 2, z),
      );
      parts.push(geo);
    }

    if (!parts.length) return null;
    const merged = mergeGeometries(parts, false);
    parts.forEach((g) => g.dispose());
    return merged;
  }, [zones]);

  const material = useMemo(() => layerMaterial(mats.glassWall(), layer, 'geometry'), [layer]);

  if (!geometry) return null;

  return <mesh geometry={geometry} material={material} raycast={() => null} />;
}
