import { useLayoutEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { FEATURE_BASE_Y } from './constants';
import { tableLegGeometry } from './geometries/sharedGeometries';
import { mats } from './materials/sharedMaterials';
import type { SvgTable } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';
import { useSceneInvalidate } from './hooks/useSceneInvalidate';

const TABLE_LEG_HEIGHT = 0.3;
const LEG_Y = FEATURE_BASE_Y + TABLE_LEG_HEIGHT / 2;
const _dummy = new THREE.Object3D();

interface LegInstance {
  x: number;
  z: number;
  scale: number;
}

function collectLegs(tables: SvgTable[]): { boxLegs: LegInstance[]; pedestals: LegInstance[] } {
  const boxLegs: LegInstance[] = [];
  const pedestals: LegInstance[] = [];

  for (const table of tables) {
    const surfaces =
      table.surfaces.length > 0 ? table.surfaces : [{ shape: 'box' as const, bbox: table.bbox }];

    for (const surface of surfaces) {
      const { width, depth } = svgBBoxToWorldSize(surface.bbox);
      const [x, , z] = svgBBoxCenterToWorld(surface.bbox);
      const w = Math.max(width, 0.08);
      const d = Math.max(depth, 0.08);

      if (surface.shape === 'cylinder') {
        const radius = Math.max(Math.min(w, d) / 2, 0.06) * 0.22;
        pedestals.push({ x, z, scale: radius / 0.018 });
      } else {
        const insetX = w * 0.38;
        const insetZ = d * 0.38;
        for (const [lx, lz] of [
          [-insetX, -insetZ],
          [insetX, -insetZ],
          [-insetX, insetZ],
          [insetX, insetZ],
        ] as [number, number][]) {
          boxLegs.push({ x: x + lx, z: z + lz, scale: 1 });
        }
      }
    }
  }

  return { boxLegs, pedestals };
}

interface InstancedTableLegsProps {
  tables: SvgTable[];
  material?: THREE.MeshStandardMaterial;
}

export function InstancedTableLegs({ tables, material }: InstancedTableLegsProps) {
  const { boxLegs, pedestals } = useMemo(() => collectLegs(tables), [tables]);
  const boxRef = useRef<THREE.InstancedMesh>(null);
  const pedRef = useRef<THREE.InstancedMesh>(null);
  const legGeo = useMemo(() => tableLegGeometry(TABLE_LEG_HEIGHT), []);

  useLayoutEffect(() => {
    if (boxRef.current) {
      boxLegs.forEach((leg, i) => {
        _dummy.position.set(leg.x, LEG_Y, leg.z);
        _dummy.scale.setScalar(leg.scale);
        _dummy.updateMatrix();
        boxRef.current!.setMatrixAt(i, _dummy.matrix);
      });
      boxRef.current.count = boxLegs.length;
      boxRef.current.instanceMatrix.needsUpdate = true;
    }

    if (pedRef.current) {
      pedestals.forEach((leg, i) => {
        _dummy.position.set(leg.x, LEG_Y, leg.z);
        _dummy.scale.set(leg.scale, 1, leg.scale);
        _dummy.updateMatrix();
        pedRef.current!.setMatrixAt(i, _dummy.matrix);
      });
      pedRef.current.count = pedestals.length;
      pedRef.current.instanceMatrix.needsUpdate = true;
    }
  }, [boxLegs, pedestals, legGeo]);

  useSceneInvalidate([boxLegs.length, pedestals.length]);

  const legMaterial = material ?? mats.tableEdge();

  return (
    <group raycast={() => null}>
      {boxLegs.length > 0 && (
        <instancedMesh ref={boxRef} args={[legGeo, legMaterial, boxLegs.length]} />
      )}
      {pedestals.length > 0 && (
        <instancedMesh ref={pedRef} args={[legGeo, legMaterial, pedestals.length]} />
      )}
    </group>
  );
}
