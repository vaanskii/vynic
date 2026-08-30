import { useMemo } from 'react';
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { FEATURE_BASE_Y, RAILING_HEIGHT } from './constants';
import { mats } from './materials/sharedMaterials';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

interface RailingMeshProps {
  zones: FloorZone[];
}

export function RailingMesh({ zones }: RailingMeshProps) {
  const geometry = useMemo(() => {
    const parts: THREE.BufferGeometry[] = [];

    for (const zone of zones) {
      const { width, depth } = svgBBoxToWorldSize(zone.bbox);
      if (width < 0.003 && depth < 0.003) continue;

      const [x, , z] = svgBBoxCenterToWorld(zone.bbox);
      const len = Math.max(Math.hypot(width, depth), 0.04);
      const angle = Math.atan2(depth, width);
      const geo = new THREE.BoxGeometry(len, RAILING_HEIGHT, 0.012);
      const matrix = new THREE.Matrix4()
        .makeTranslation(x, FEATURE_BASE_Y + RAILING_HEIGHT / 2, z)
        .multiply(new THREE.Matrix4().makeRotationY(-angle));
      geo.applyMatrix4(matrix);
      parts.push(geo);
    }

    if (!parts.length) return null;
    const merged = mergeGeometries(parts, false);
    parts.forEach((g) => g.dispose());
    return merged;
  }, [zones]);

  if (!geometry) return null;

  return <mesh geometry={geometry} material={mats.railing()} raycast={() => null} />;
}
