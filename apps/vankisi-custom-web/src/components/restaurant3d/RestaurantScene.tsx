import { memo, useCallback, useLayoutEffect, useMemo, useState } from 'react';
import { useThree } from '@react-three/fiber';
import { ConnectedPolesMesh } from './ConnectedPolesMesh';
import { SceneCameraRig } from './controls/SceneCameraRig';
import { BarDetailMesh } from './BarDetailMesh';
import { EntranceMesh } from './EntranceMesh';
import { Floor } from './Floor';
import { GlassWallMesh } from './GlassWallMesh';
import { useSceneInvalidate } from './hooks/useSceneInvalidate';
import { InstancedPoles } from './InstancedPoles';
import { InstancedTableLegs } from './InstancedTableLegs';
import { Floor2RailingMesh } from './Floor2RailingMesh';
import { FloorDebugOverlay } from './FloorDebugOverlay';
import { PhotoZoneMesh } from './PhotoZoneMesh';
import { RestroomMesh } from './RestroomMesh';
import { SceneLighting } from './SceneLighting';
import { StageDetailMesh } from './StageDetailMesh';
import { StaticWallsMesh } from './StaticWallsMesh';
import { StairsMesh } from './StairsMesh';
import { TableMesh } from './TableMesh';
import { TablePointerHandler } from './TablePointerHandler';
import { ZoneMesh } from './ZoneMesh';
import { mats } from './materials/sharedMaterials';
import { applyFloorLayerOpacities, layerMaterial, syncAllLayerMaterials, type FloorLayerId } from './materials/ghostMaterials';
import {
  FloorTransitionProvider,
  useFloorTransition,
} from './context/FloorTransitionContext';
import { FLOOR2_ELEVATION } from './constants';
import type { FloorId, FloorPlanData, TableState } from './types';
import type { InteractionMode } from './types/sceneMode';
import {
  getOverviewCamera,
  getTopDownView,
  isTopDownPolarAngle,
  offsetCameraXZ,
} from './utils/cameraView';
import { getViewBox } from './utils/coordinates';
import { computeFloor2GhostOffset } from './utils/floorAlignment';
import { matchPoleColumns } from './utils/poleMatching';
import { getTableState } from './utils/tableStateLookup';

interface StaticSceneProps {
  floorPlan: FloorPlanData;
  layer: FloorLayerId;
  interactive: boolean;
  floorDebug?: boolean;
  hideStairs?: boolean;
  excludePoleIds?: ReadonlySet<string>;
}

/** Parsed geometry — never re-renders on table status changes */
export const StaticSceneContent = memo(function StaticSceneContent({
  floorPlan,
  layer,
  interactive,
  floorDebug,
  hideStairs = false,
  excludePoleIds,
}: StaticSceneProps) {
  const isFloor2 = floorPlan.floorId === 'floor2';

  const wallMat = useMemo(() => layerMaterial(mats.wall(), layer, 'geometry'), [layer]);
  const structureMat = useMemo(() => layerMaterial(mats.structure(), layer, 'geometry'), [layer]);
  const poleMat = useMemo(() => layerMaterial(mats.pole(), layer, 'geometry'), [layer]);
  const legMat = useMemo(() => layerMaterial(mats.tableEdge(), layer, 'geometry'), [layer]);

  const { walls, structures, barZones, poles, stairSteps, entranceDoorways, stageZone, glassWalls, photoZones, featureZones } =
    useMemo(() => {
      const zones = floorPlan.zones;
      return {
        walls: zones.filter((z) => z.kind === 'wall'),
        structures: zones.filter((z) => z.kind === 'structure'),
        barZones: zones.filter((z) => z.kind === 'bar'),
        poles: zones.filter((z) => z.kind === 'pole' && z.id !== 'pole-Pole-1'),
        stairSteps: zones.filter((z) => z.kind === 'stair-step'),
        entranceDoorways: zones.filter((z) => z.kind === 'entrance'),
        stageZone: zones.find((z) => z.kind === 'stage'),
        glassWalls: zones.filter((z) => z.kind === 'glass-wall'),
        photoZones: zones.filter((z) => z.kind === 'photo-zone'),
        featureZones: zones.filter(
          (z) =>
            ![
              'wall',
              'structure',
              'pole',
              'arrow',
              'stair-step',
              'entrance',
              'bar',
              'stage',
              'glass-wall',
              'photo-zone',
              'railing',
              'restroom',
            ].includes(z.kind),
        ),
      };
    }, [floorPlan.zones]);

  return (
    <group raycast={interactive ? undefined : () => null}>
      <Floor
        boundary={floorPlan.boundary}
        floorId={floorPlan.floorId}
        stairOpening={isFloor2 ? floorPlan.stairOpening : undefined}
        floorSlabs={floorPlan.floorSlabs}
        layer={layer}
      />
      <StaticWallsMesh
        walls={walls}
        structures={structures}
        wallMaterial={wallMat}
        structureMaterial={structureMat}
      />
      {featureZones.map((zone) => (
        <ZoneMesh key={zone.id} zone={zone} layer={layer} />
      ))}
      {!isFloor2 && (
        <>
          {barZones.map((zone) => (
            <ZoneMesh key={zone.id} zone={zone} layer={layer} />
          ))}
          {stageZone && <ZoneMesh zone={stageZone} layer={layer} />}
          {interactive && <BarDetailMesh barZones={barZones} />}
          {interactive && <StageDetailMesh stageZone={stageZone} />}
          <EntranceMesh doorways={entranceDoorways} layer={layer} />
        </>
      )}
      {isFloor2 && (
        <>
          <GlassWallMesh zones={glassWalls} layer={layer} />
          <PhotoZoneMesh zones={photoZones} layer={layer} />
          {floorPlan.restrooms && floorPlan.restrooms.length > 0 && (
            <RestroomMesh restrooms={floorPlan.restrooms} layer={layer} />
          )}
          {floorPlan.railingSegments && floorPlan.railingSegments.length > 0 && (
            <Floor2RailingMesh
              segments={floorPlan.railingSegments.filter((s) => s.space !== 'world')}
              layer={layer}
            />
          )}
          {floorDebug && interactive && <FloorDebugOverlay floorSlabs={floorPlan.floorSlabs} />}
        </>
      )}
      <InstancedPoles
        poles={excludePoleIds ? poles.filter((p) => !excludePoleIds.has(p.id)) : poles}
        material={poleMat}
      />
      <InstancedTableLegs tables={floorPlan.tables} material={legMat} />
      {!hideStairs && <StairsMesh steps={stairSteps} variant="ascend" />}
    </group>
  );
});

interface InteractiveTablesProps {
  tables: FloorPlanData['tables'];
  tableStates: Map<string, TableState>;
  selectedTableIds: string[];
  interactionMode: InteractionMode;
  layer: FloorLayerId;
  interactive: boolean;
}

/** Only table tops re-render when status / selection changes */
export const InteractiveTables = memo(function InteractiveTables({
  tables,
  tableStates,
  selectedTableIds,
  interactionMode,
  layer,
  interactive,
}: InteractiveTablesProps) {
  const selectedSet = useMemo(() => new Set(selectedTableIds), [selectedTableIds]);

  useSceneInvalidate([tableStates, selectedTableIds, interactionMode, layer, interactive]);

  return (
    <group raycast={interactive ? undefined : () => null}>
      {tables.map((table) => (
        <TableMesh
          key={table.id}
          table={table}
          status={getTableState(tableStates, table.id)?.status ?? 'unknown'}
          isSelected={interactive && selectedSet.has(table.id)}
          layer={layer}
          interactive={interactive}
        />
      ))}
    </group>
  );
});

interface RestaurantSceneProps {
  floor1Plan: FloorPlanData;
  floor2Plan: FloorPlanData;
  activeFloor: FloorId;
  tableStates: Map<string, TableState>;
  selectedTableIds: string[];
  onTableClick: (tableId: string) => void;
  interactionMode: InteractionMode;
  floorDebug?: boolean;
}

export function RestaurantScene(props: RestaurantSceneProps) {
  return (
    <FloorTransitionProvider targetFloor={props.activeFloor}>
      <RestaurantSceneInner {...props} />
    </FloorTransitionProvider>
  );
}

/** Re-apply ghost opacities when floor 2 preview mounts/unmounts (e.g. leaving top-down) */
function FloorOpacityRemountSync({ floor2Visible }: { floor2Visible: boolean }) {
  const { blendRef, floor1GroupRef, floor2GroupRef } = useFloorTransition();
  const invalidate = useThree((s) => s.invalidate);

  useLayoutEffect(() => {
    const blend = blendRef.current ?? 0;
    applyFloorLayerOpacities(blend, floor1GroupRef.current, floor2GroupRef.current);
    invalidate();
  }, [floor2Visible, blendRef, floor1GroupRef, floor2GroupRef, invalidate]);

  return null;
}

/** Re-sync materials when interactive layer toggles after a floor switch */
function FloorInteractiveSync({
  floor1Interactive,
  floor2Interactive,
}: {
  floor1Interactive: boolean;
  floor2Interactive: boolean;
}) {
  const { blendRef, floor1GroupRef, floor2GroupRef } = useFloorTransition();
  const invalidate = useThree((s) => s.invalidate);

  useLayoutEffect(() => {
    const blend = blendRef.current ?? 0;
    syncAllLayerMaterials(blend);
    applyFloorLayerOpacities(blend, floor1GroupRef.current, floor2GroupRef.current);
    invalidate();
  }, [floor1Interactive, floor2Interactive, blendRef, floor1GroupRef, floor2GroupRef, invalidate]);

  return null;
}

function RestaurantSceneInner({
  floor1Plan,
  floor2Plan,
  activeFloor,
  tableStates,
  selectedTableIds,
  onTableClick,
  interactionMode,
  floorDebug,
}: RestaurantSceneProps) {
  const sceneWidth = getViewBox().width * 0.01;
  const { floor1GroupRef, floor2GroupRef, targetFloor } = useFloorTransition();
  const mobile = interactionMode === 'mobile';

  const [polarAngle, setPolarAngle] = useState(Math.PI / 2);
  const handlePolarAngleChange = useCallback((angle: number) => {
    setPolarAngle(angle);
  }, []);
  const isTopDown = isTopDownPolarAngle(polarAngle);
  const hideFloor2Preview = activeFloor === 'floor1' && isTopDown;
  const floor1Interactive = targetFloor === 'floor1';
  const floor2Interactive = targetFloor === 'floor2';

  const floor2Offset = useMemo(() => {
    const floor1Anchor = floor1Plan.alignAnchor;
    const floor2Anchor = floor2Plan.alignAnchor;
    if (!floor1Anchor || !floor2Anchor) return [0, 0, 0] as [number, number, number];
    return computeFloor2GhostOffset(floor1Anchor, floor2Anchor);
  }, [floor1Plan.alignAnchor, floor2Plan.alignAnchor]);

  const floor1Camera = useMemo(
    () => getOverviewCamera(floor1Plan, sceneWidth, mobile),
    [floor1Plan, sceneWidth, mobile],
  );

  const floor2Camera = useMemo(
    () => offsetCameraXZ(getOverviewCamera(floor2Plan, sceneWidth, mobile), floor2Offset),
    [floor2Plan, sceneWidth, mobile, floor2Offset],
  );

  const floorOverviewView = useMemo(
    () => getTopDownView(floor1Plan, sceneWidth, mobile, floor1Camera.fov),
    [floor1Plan, sceneWidth, mobile, floor1Camera.fov],
  );

  const ghostStairSteps = useMemo(
    () => floor2Plan.zones.filter((z) => z.kind === 'stair-step'),
    [floor2Plan.zones],
  );

  const worldRailingSegments = useMemo(
    () => (floor2Plan.railingSegments ?? []).filter((s) => s.space === 'world'),
    [floor2Plan.railingSegments],
  );

  const poleConnections = useMemo(() => {
    const floor1Poles = floor1Plan.zones.filter(
      (z) => z.kind === 'pole' && z.id !== 'pole-Pole-1',
    );
    const floor2Poles = floor2Plan.zones.filter((z) => z.kind === 'pole');
    return matchPoleColumns(floor1Poles, floor2Poles, [0, 0, 0], floor2Offset);
  }, [floor1Plan.zones, floor2Plan.zones, floor2Offset]);

  const connectedFloor1PoleIds = useMemo(
    () => new Set(poleConnections.map((c) => c.floor1Id)),
    [poleConnections],
  );
  const connectedFloor2PoleIds = useMemo(
    () => new Set(poleConnections.map((c) => c.floor2Id)),
    [poleConnections],
  );

  return (
    <>
      <FloorOpacityRemountSync floor2Visible={!hideFloor2Preview} />
      <FloorInteractiveSync
        floor1Interactive={floor1Interactive}
        floor2Interactive={floor2Interactive}
      />
      <SceneLighting sceneWidth={sceneWidth} />

      {poleConnections.length > 0 && !hideFloor2Preview && (
        <ConnectedPolesMesh connections={poleConnections} />
      )}

      {ghostStairSteps.length > 0 && (
        <group position={[floor2Offset[0], 0, floor2Offset[2]]}>
          <StairsMesh steps={ghostStairSteps} variant="between-floors" />
        </group>
      )}

      {worldRailingSegments.length > 0 && (
        <group position={[floor2Offset[0], 0, floor2Offset[2]]}>
          <Floor2RailingMesh segments={worldRailingSegments} />
        </group>
      )}

      <group ref={floor1GroupRef} position={[0, 0, 0]}>
        <StaticSceneContent
          floorPlan={floor1Plan}
          layer="floor1"
          interactive={floor1Interactive}
          floorDebug={floorDebug}
          hideStairs
          excludePoleIds={connectedFloor1PoleIds}
        />
        <InteractiveTables
          tables={floor1Plan.tables}
          tableStates={tableStates}
          selectedTableIds={floor1Interactive ? selectedTableIds : []}
          interactionMode={interactionMode}
          layer="floor1"
          interactive={floor1Interactive}
        />
      </group>

      {!hideFloor2Preview && (
        <group
          ref={floor2GroupRef}
          position={[floor2Offset[0], FLOOR2_ELEVATION, floor2Offset[2]]}
        >
          <StaticSceneContent
            floorPlan={floor2Plan}
            layer="floor2"
            interactive={floor2Interactive}
            hideStairs
            excludePoleIds={connectedFloor2PoleIds}
          />
          <InteractiveTables
            tables={floor2Plan.tables}
            tableStates={tableStates}
            selectedTableIds={floor2Interactive ? selectedTableIds : []}
            interactionMode={interactionMode}
            layer="floor2"
            interactive={floor2Interactive}
          />
        </group>
      )}

      <TablePointerHandler
        onTableClick={onTableClick}
        enabled={targetFloor === 'floor1' ? floor1Interactive : floor2Interactive}
      />

      <SceneCameraRig
        sceneWidth={sceneWidth}
        floor1View={floor1Camera}
        floor2View={floor2Camera}
        fixedOrbitView={floorOverviewView}
        onPolarAngleChange={handlePolarAngleChange}
      />
    </>
  );
}
