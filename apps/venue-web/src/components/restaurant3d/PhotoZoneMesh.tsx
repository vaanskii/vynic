import { useMemo } from 'react';
import * as THREE from 'three';
import { FEATURE_BASE_Y, PHOTO_ZONE_HEIGHT } from './constants';
import { layerMaterial, registerLayerMaterial, type FloorLayerId } from './materials/ghostMaterials';
import { mats } from './materials/sharedMaterials';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

interface PhotoZoneMeshProps {
  zones: FloorZone[];
  layer: FloorLayerId;
}

export function PhotoZoneMesh({ zones, layer }: PhotoZoneMeshProps) {
  const padMat = useMemo(() => layerMaterial(mats.photoZone(), layer, 'geometry'), [layer]);
  const trimMat = useMemo(
    () => registerLayerMaterial(new THREE.MeshStandardMaterial({ color: '#2a2218', roughness: 0.4, metalness: 0.2 }), layer, 'geometry'),
    [layer],
  );

  return (
    <>
      {zones.map((zone) => {
        const { width, depth } = svgBBoxToWorldSize(zone.bbox);
        const [x, , z] = svgBBoxCenterToWorld(zone.bbox);
        if (width < 0.08 || depth < 0.08) return null;

        return (
          <group key={zone.id} position={[x, 0, z]} raycast={() => null}>
            <mesh position={[0, FEATURE_BASE_Y + PHOTO_ZONE_HEIGHT / 2, 0]}>
              <boxGeometry args={[width, PHOTO_ZONE_HEIGHT, depth]} />
              <primitive object={padMat} attach="material" />
            </mesh>
            <mesh position={[0, FEATURE_BASE_Y + PHOTO_ZONE_HEIGHT + 0.02, 0]} material={trimMat}>
              <boxGeometry args={[width * 0.92, 0.018, depth * 0.92]} />
            </mesh>
          </group>
        );
      })}
    </>
  );
}
