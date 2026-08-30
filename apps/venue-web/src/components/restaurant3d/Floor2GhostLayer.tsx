import { memo, useLayoutEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { Floor } from './Floor';
import { Floor2RailingMesh } from './Floor2RailingMesh';
import { GlassWallMesh } from './GlassWallMesh';
import { InstancedPoles } from './InstancedPoles';
import { InstancedTableLegs } from './InstancedTableLegs';
import { PhotoZoneMesh } from './PhotoZoneMesh';
import { RestroomMesh } from './RestroomMesh';
import { StaticWallsMesh } from './StaticWallsMesh';
import { TableMesh } from './TableMesh';
import { applyFloorLayerOpacities, layerMaterial } from './materials/ghostMaterials';
import { mats } from './materials/sharedMaterials';
import type { FloorPlanData, TableState } from './types';
import { getTableState } from './utils/tableStateLookup';

interface Floor2GhostLayerProps {
  floorPlan: FloorPlanData;
  tableStates: Map<string, TableState>;
  excludePoleIds?: ReadonlySet<string>;
}

export const Floor2GhostLayer = memo(function Floor2GhostLayer({
  floorPlan,
  tableStates,
  excludePoleIds,
}: Floor2GhostLayerProps) {
  const groupRef = useRef<THREE.Group>(null);
  const wallMat = useMemo(() => layerMaterial(mats.wall(), 'floor2', 'geometry'), []);
  const structureMat = useMemo(() => layerMaterial(mats.structure(), 'floor2', 'geometry'), []);
  const legMat = useMemo(() => layerMaterial(mats.tableEdge(), 'floor2', 'geometry'), []);
  const poleMat = useMemo(() => layerMaterial(mats.pole(), 'floor2', 'geometry'), []);

  useLayoutEffect(() => {
    applyFloorLayerOpacities(0, null, groupRef.current);
  }, []);

  const { walls, structures, poles, glassWalls, photoZones, railingSegments } = useMemo(() => {
    const zones = floorPlan.zones;
    return {
      walls: zones.filter((z) => z.kind === 'wall'),
      structures: zones.filter((z) => z.kind === 'structure'),
      poles: zones.filter((z) => z.kind === 'pole' && !excludePoleIds?.has(z.id)),
      glassWalls: zones.filter((z) => z.kind === 'glass-wall'),
      photoZones: zones.filter((z) => z.kind === 'photo-zone'),
      railingSegments: (floorPlan.railingSegments ?? []).filter((s) => s.space !== 'world'),
    };
  }, [floorPlan.zones, floorPlan.railingSegments, excludePoleIds]);

  return (
    <group ref={groupRef} renderOrder={10} raycast={() => null}>
      <Floor
        boundary={floorPlan.boundary}
        floorId="floor2"
        floorSlabs={floorPlan.floorSlabs}
        stairOpening={floorPlan.stairOpening}
        layer="floor2"
      />
      <StaticWallsMesh
        walls={walls}
        structures={structures}
        wallMaterial={wallMat}
        structureMaterial={structureMat}
      />
      <GlassWallMesh zones={glassWalls} layer="floor2" />
      <PhotoZoneMesh zones={photoZones} layer="floor2" />
      {floorPlan.restrooms && floorPlan.restrooms.length > 0 && (
        <RestroomMesh restrooms={floorPlan.restrooms} layer="floor2" />
      )}
      {railingSegments.length > 0 && (
        <Floor2RailingMesh segments={railingSegments} layer="floor2" />
      )}
      <InstancedPoles poles={poles} material={poleMat} />
      <InstancedTableLegs tables={floorPlan.tables} material={legMat} />
      {floorPlan.tables.map((table) => (
        <TableMesh
          key={table.id}
          table={table}
          status={getTableState(tableStates, table.id)?.status ?? 'unknown'}
          isSelected={false}
          layer="floor2"
          interactive={false}
        />
      ))}
    </group>
  );
});
