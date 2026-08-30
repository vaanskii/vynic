import { useMemo } from 'react';
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { FEATURE_BASE_Y } from './constants';
import { mats } from './materials/sharedMaterials';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

interface MergedZoneProps {
  zones: FloorZone[];
  material: THREE.MeshStandardMaterial;
}

function MergedBoxes({ zones, material }: MergedZoneProps) {
  const geometry = useMemo(() => {
    const parts: THREE.BufferGeometry[] = [];

    for (const zone of zones) {
      const { width, depth } = svgBBoxToWorldSize(zone.bbox);
      if (width < 0.015 && depth < 0.015) continue;

      const [x, , z] = svgBBoxCenterToWorld(zone.bbox);
      const h = zone.kind === 'wall' ? 0.32 : 0.34;
      const geo = new THREE.BoxGeometry(Math.max(width, 0.04), h, Math.max(depth, 0.04));
      geo.applyMatrix4(new THREE.Matrix4().makeTranslation(x, FEATURE_BASE_Y + h / 2, z));
      parts.push(geo);
    }

    if (!parts.length) return null;
    const merged = mergeGeometries(parts, false);
    parts.forEach((g) => g.dispose());
    return merged;
  }, [zones]);

  if (!geometry) return null;

  return (
    <mesh geometry={geometry} material={material} raycast={() => null} />
  );
}

interface StaticWallsMeshProps {
  walls: FloorZone[];
  structures: FloorZone[];
  wallMaterial?: THREE.MeshStandardMaterial;
  structureMaterial?: THREE.MeshStandardMaterial;
}

export function StaticWallsMesh({
  walls,
  structures,
  wallMaterial,
  structureMaterial,
}: StaticWallsMeshProps) {
  return (
    <group>
      <MergedBoxes zones={walls} material={wallMaterial ?? mats.wall()} />
      <MergedBoxes zones={structures} material={structureMaterial ?? mats.structure()} />
    </group>
  );
}
