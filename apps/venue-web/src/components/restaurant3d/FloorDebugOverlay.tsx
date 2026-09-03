import { useMemo } from 'react';
import * as THREE from 'three';
import { FLOOR_Y } from './constants';
import type { FloorSlab } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

interface FloorDebugOverlayProps {
  floorSlabs?: FloorSlab[];
}

const SLAB_COLOR = '#4ade80';

function slabMaterial(color: string): THREE.MeshBasicMaterial {
  return new THREE.MeshBasicMaterial({
    color,
    transparent: true,
    opacity: 0.42,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
}

export function FloorDebugOverlay({ floorSlabs }: FloorDebugOverlayProps) {
  const activeMat = useMemo(() => slabMaterial(SLAB_COLOR), []);
  const slabs = floorSlabs ?? [];

  if (!slabs.length) return null;

  return (
    <group raycast={() => null}>
      {slabs.map((slab) => {
        const { width, depth } = svgBBoxToWorldSize(slab.bbox);
        const [cx, , cz] = svgBBoxCenterToWorld(slab.bbox);
        return (
          <mesh
            key={slab.id}
            position={[cx, FLOOR_Y + 0.02, cz]}
            rotation={[-Math.PI / 2, 0, 0]}
          >
            <planeGeometry args={[width, depth]} />
            <primitive object={activeMat} attach="material" />
          </mesh>
        );
      })}
    </group>
  );
}
