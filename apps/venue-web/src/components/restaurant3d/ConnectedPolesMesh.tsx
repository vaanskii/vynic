import { useLayoutEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { FEATURE_BASE_Y, FLOOR1_GHOST_OPACITY, FLOOR2_ELEVATION, POLE_HEIGHT } from './constants';
import { poleGeometry } from './geometries/sharedGeometries';
import { ghostMaterial } from './materials/ghostMaterials';
import { mats } from './materials/sharedMaterials';
import type { PoleConnection } from './utils/poleMatching';
import { useSceneInvalidate } from './hooks/useSceneInvalidate';

const _dummy = new THREE.Object3D();

const FLOOR2_SURFACE_Y = FLOOR2_ELEVATION + FEATURE_BASE_Y;
const LOWER_BASE_Y = FEATURE_BASE_Y;
const LOWER_HEIGHT = FLOOR2_SURFACE_Y - LOWER_BASE_Y;
const UPPER_HEIGHT = POLE_HEIGHT;

interface ConnectedPolesMeshProps {
  connections: PoleConnection[];
}

export function ConnectedPolesMesh({ connections }: ConnectedPolesMeshProps) {
  const lowerRef = useRef<THREE.InstancedMesh>(null);
  const upperRef = useRef<THREE.InstancedMesh>(null);
  const geo = useMemo(() => poleGeometry(POLE_HEIGHT, 0.05), []);

  const lowerMat = useMemo(
    () => ghostMaterial(mats.pole(), FLOOR1_GHOST_OPACITY, 'ghost-connected-pole-lower'),
    [],
  );
  const upperMat = useMemo(() => mats.pole(), []);

  useLayoutEffect(() => {
    if (!lowerRef.current || !upperRef.current) return;

    connections.forEach((pole, i) => {
      const scale = pole.radius / 0.05;

      _dummy.position.set(pole.x, LOWER_BASE_Y + LOWER_HEIGHT / 2, pole.z);
      _dummy.scale.set(scale, LOWER_HEIGHT / POLE_HEIGHT, scale);
      _dummy.updateMatrix();
      lowerRef.current!.setMatrixAt(i, _dummy.matrix);

      _dummy.position.set(pole.x, FLOOR2_SURFACE_Y + UPPER_HEIGHT / 2, pole.z);
      _dummy.scale.set(scale, UPPER_HEIGHT / POLE_HEIGHT, scale);
      _dummy.updateMatrix();
      upperRef.current!.setMatrixAt(i, _dummy.matrix);
    });

    lowerRef.current.count = connections.length;
    upperRef.current.count = connections.length;
    lowerRef.current.instanceMatrix.needsUpdate = true;
    upperRef.current.instanceMatrix.needsUpdate = true;
  }, [connections, geo]);

  useSceneInvalidate([connections.length]);

  if (!connections.length) return null;

  return (
    <group renderOrder={5} raycast={() => null}>
      <instancedMesh
        ref={lowerRef}
        args={[geo, lowerMat, connections.length]}
        raycast={() => null}
      />
      <instancedMesh
        ref={upperRef}
        args={[geo, upperMat, connections.length]}
        raycast={() => null}
      />
    </group>
  );
}
