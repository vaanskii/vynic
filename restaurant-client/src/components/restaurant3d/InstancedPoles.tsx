import { useLayoutEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { FEATURE_BASE_Y, POLE_HEIGHT } from './constants';
import { poleGeometry } from './geometries/sharedGeometries';
import { mats } from './materials/sharedMaterials';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';
import { useSceneInvalidate } from './hooks/useSceneInvalidate';

const _dummy = new THREE.Object3D();

interface InstancedPolesProps {
  poles: FloorZone[];
  material?: THREE.MeshStandardMaterial;
}

export function InstancedPoles({ poles, material }: InstancedPolesProps) {
  const instances = useMemo(
    () =>
      poles.map((zone) => {
        const { width, depth } = svgBBoxToWorldSize(zone.bbox);
        const [x, , z] = svgBBoxCenterToWorld(zone.bbox);
        const radius = Math.max(Math.min(width, depth) / 2, 0.05);
        return { x, z, radius };
      }),
    [poles],
  );

  const ref = useRef<THREE.InstancedMesh>(null);
  const geo = useMemo(() => poleGeometry(POLE_HEIGHT, 0.05), []);

  useLayoutEffect(() => {
    if (!ref.current) return;
    instances.forEach((p, i) => {
      _dummy.position.set(p.x, FEATURE_BASE_Y + POLE_HEIGHT / 2, p.z);
      _dummy.scale.set(p.radius / 0.05, 1, p.radius / 0.05);
      _dummy.updateMatrix();
      ref.current!.setMatrixAt(i, _dummy.matrix);
    });
    ref.current.count = instances.length;
    ref.current.instanceMatrix.needsUpdate = true;
  }, [instances, geo]);

  useSceneInvalidate([instances.length]);

  if (!instances.length) return null;

  const poleMaterial = material ?? mats.pole();

  return (
    <instancedMesh
      ref={ref}
      args={[geo, poleMaterial, instances.length]}
      raycast={() => null}
    />
  );
}
