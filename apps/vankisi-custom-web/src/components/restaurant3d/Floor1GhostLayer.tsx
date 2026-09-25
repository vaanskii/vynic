import { memo, useLayoutEffect, useMemo, useRef } from 'react';
import * as THREE from 'three';
import { EntranceMesh } from './EntranceMesh';
import { Floor } from './Floor';
import { InstancedPoles } from './InstancedPoles';
import { InstancedTableLegs } from './InstancedTableLegs';
import { StaticWallsMesh } from './StaticWallsMesh';
import { TableMesh } from './TableMesh';
import { ZoneMesh } from './ZoneMesh';
import { applyFloorLayerOpacities } from './materials/ghostMaterials';
import { layerMaterial } from './materials/ghostMaterials';
import { mats } from './materials/sharedMaterials';
import type { FloorPlanData, SvgBBox, TableState } from './types';
import { getTableState } from './utils/tableStateLookup';

interface Floor1GhostLayerProps {
  floorPlan: FloorPlanData;
  tableStates: Map<string, TableState>;
  stairOpening?: SvgBBox;
  excludePoleIds?: ReadonlySet<string>;
}

export const Floor1GhostLayer = memo(function Floor1GhostLayer({
  floorPlan,
  tableStates,
  stairOpening,
  excludePoleIds,
}: Floor1GhostLayerProps) {
  const groupRef = useRef<THREE.Group>(null);
  const wallMat = useMemo(() => layerMaterial(mats.wall(), 'floor1', 'geometry'), []);
  const structureMat = useMemo(() => layerMaterial(mats.structure(), 'floor1', 'geometry'), []);
  const legMat = useMemo(() => layerMaterial(mats.tableEdge(), 'floor1', 'geometry'), []);
  const poleMat = useMemo(() => layerMaterial(mats.pole(), 'floor1', 'geometry'), []);

  useLayoutEffect(() => {
    applyFloorLayerOpacities(1, groupRef.current, null);
  }, []);

  const { walls, structures, barZones, poles, entranceDoorways, stageZone } = useMemo(() => {
    const zones = floorPlan.zones;
    return {
      walls: zones.filter((z) => z.kind === 'wall'),
      structures: zones.filter((z) => z.kind === 'structure'),
      barZones: zones.filter((z) => z.kind === 'bar'),
      poles: zones.filter(
        (z) => z.kind === 'pole' && z.id !== 'pole-Pole-1' && !excludePoleIds?.has(z.id),
      ),
      entranceDoorways: zones.filter((z) => z.kind === 'entrance'),
      stageZone: zones.find((z) => z.kind === 'stage'),
    };
  }, [floorPlan.zones, excludePoleIds]);

  return (
    <group ref={groupRef} renderOrder={0} raycast={() => null}>
      <Floor
        boundary={floorPlan.boundary}
        floorId="floor1"
        floorSlabs={floorPlan.floorSlabs}
        layer="floor1"
        stairOpening={stairOpening}
      />
      <StaticWallsMesh
        walls={walls}
        structures={structures}
        wallMaterial={wallMat}
        structureMaterial={structureMat}
      />
      {barZones.map((zone) => (
        <ZoneMesh key={zone.id} zone={zone} layer="floor1" />
      ))}
      {stageZone && <ZoneMesh zone={stageZone} layer="floor1" />}
      <EntranceMesh doorways={entranceDoorways} layer="floor1" />
      <InstancedPoles poles={poles} material={poleMat} />
      <InstancedTableLegs tables={floorPlan.tables} material={legMat} />
      {floorPlan.tables.map((table) => (
        <TableMesh
          key={table.id}
          table={table}
          status={getTableState(tableStates, table.id)?.status ?? 'unknown'}
          isSelected={false}
          layer="floor1"
          interactive={false}
        />
      ))}
    </group>
  );
});
