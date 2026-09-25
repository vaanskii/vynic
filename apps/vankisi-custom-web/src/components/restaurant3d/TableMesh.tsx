import { memo, useRef, useState, useEffect, useCallback, useMemo } from 'react';
import { Text } from '@react-three/drei';
import { useFrame, useThree, type ThreeEvent } from '@react-three/fiber';
import * as THREE from 'three';
import {
  ANIMATION_SPEED,
  FEATURE_BASE_Y,
  HOVER_RING_COLOR,
  HOVER_SCALE,
  SELECTED_RING_COLOR,
  SELECTED_SCALE,
} from './constants';
import { useSceneMode } from './context/SceneModeContext';
import { mats, getStatusMaterial } from './materials/sharedMaterials';
import { layerMaterial, syncLayerMaterialOpacity, type FloorLayerId } from './materials/ghostMaterials';
import { useFloorTransition } from './context/FloorTransitionContext';
import { MOBILE_SELECT_SCALE } from './types/sceneMode';
import type { SvgBBox, SvgTable, TableStatus } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';
import { computeTableLayout } from './utils/tableLayout';
import { tableDisplayNumber } from './mapLabels';

const TABLE_TOP_THICKNESS = 0.042;
const TABLE_LEG_HEIGHT = 0.3;
const MOBILE_ANIMATION_SPEED = 10;

interface TableTopProps {
  tableId: string;
  shape: 'box' | 'cylinder';
  bbox: SvgBBox;
  localX: number;
  localZ: number;
  status: TableStatus;
  isSelected: boolean;
  isHovered: boolean;
  onHoverChange: (hovered: boolean) => void;
  layer: FloorLayerId;
  interactive: boolean;
}

const TableTop = memo(function TableTop({
  tableId,
  shape,
  bbox,
  localX,
  localZ,
  status,
  isSelected,
  isHovered,
  onHoverChange,
  layer,
  interactive,
}: TableTopProps) {
  const mode = useSceneMode();
  const mobile = mode === 'mobile';
  const meshRef = useRef<THREE.Mesh>(null);
  const invalidate = useThree((s) => s.invalidate);
  const highlighted = isHovered || isSelected;
  const isGhost = !interactive;

  const { width, depth } = svgBBoxToWorldSize(bbox);
  const topY = FEATURE_BASE_Y + TABLE_LEG_HEIGHT + TABLE_TOP_THICKNESS / 2;
  const w = Math.max(width, 0.08);
  const d = Math.max(depth, 0.08);

  const { blendRef } = useFloorTransition();

  useEffect(() => {
    if (!meshRef.current) return;
    const base = interactive
      ? getStatusMaterial(status, highlighted, mobile, isSelected)
      : getStatusMaterial(status, false, mobile, false);
    const mat = layerMaterial(base, layer, 'table');
    meshRef.current.material = mat;
    syncLayerMaterialOpacity(mat, blendRef.current ?? 0);
    invalidate();
  }, [status, highlighted, isSelected, mobile, layer, interactive, blendRef, invalidate]);

  const handleOver = useCallback(
    (e: ThreeEvent<PointerEvent>) => {
      if (mobile || isGhost) return;
      e.stopPropagation();
      onHoverChange(true);
      document.body.style.cursor = 'pointer';
      invalidate();
    },
    [mobile, isGhost, onHoverChange, invalidate],
  );

  const handleOut = useCallback(
    (e: ThreeEvent<PointerEvent>) => {
      if (mobile || isGhost) return;
      e.stopPropagation();
      onHoverChange(false);
      document.body.style.cursor = 'auto';
      invalidate();
    },
    [mobile, isGhost, onHoverChange, invalidate],
  );

  const pointerHandlers = isGhost
    ? { raycast: () => null }
    : mobile
      ? {}
      : { onPointerOver: handleOver, onPointerOut: handleOut };

  return (
    <group position={[localX, 0, localZ]}>
      {shape === 'cylinder' ? (
        <group>
          <mesh
            ref={meshRef}
            position={[0, topY, 0]}
            userData={{ tableId }}
            {...pointerHandlers}
          >
            <cylinderGeometry args={[Math.max(Math.min(w, d) / 2, 0.06), Math.max(Math.min(w, d) / 2, 0.06), TABLE_TOP_THICKNESS, 12]} />
            <primitive object={getStatusMaterial(status, highlighted, mobile, isSelected)} attach="material" />
          </mesh>
          <mesh position={[0, topY - TABLE_TOP_THICKNESS * 0.55, 0]} raycast={() => null}>
            <cylinderGeometry args={[Math.max(Math.min(w, d) / 2, 0.06) * 1.02, Math.max(Math.min(w, d) / 2, 0.06) * 1.02, 0.012, 10]} />
            <primitive object={mats.tableEdge()} attach="material" />
          </mesh>
        </group>
      ) : (
        <group>
          <mesh
            ref={meshRef}
            position={[0, topY, 0]}
            userData={{ tableId }}
            {...pointerHandlers}
          >
            <boxGeometry args={[w, TABLE_TOP_THICKNESS, d]} />
            <primitive object={getStatusMaterial(status, highlighted, mobile, isSelected)} attach="material" />
          </mesh>
          <mesh position={[0, topY - TABLE_TOP_THICKNESS * 0.55, 0]} raycast={() => null}>
            <boxGeometry args={[w * 1.02, 0.012, d * 1.02]} />
            <primitive object={mats.tableEdge()} attach="material" />
          </mesh>
        </group>
      )}
    </group>
  );
});

interface SelectionRingProps {
  inner: number;
  outer: number;
  selected: boolean;
  mobile: boolean;
}

function SelectionRing({ inner, outer, selected, mobile }: SelectionRingProps) {
  return (
    <mesh position={[0, 0.12, 0]} rotation={[-Math.PI / 2, 0, 0]} raycast={() => null}>
      <ringGeometry args={[inner, outer, mobile ? 24 : 32]} />
      <meshBasicMaterial
        color={selected ? SELECTED_RING_COLOR : HOVER_RING_COLOR}
        transparent
        opacity={selected ? 0.95 : 0.65}
        side={THREE.DoubleSide}
      />
    </mesh>
  );
}

function TableNumberLabel({
  tableId,
  topY,
  span,
  interactive,
  isSelected,
}: {
  tableId: string;
  topY: number;
  span: number;
  interactive: boolean;
  isSelected: boolean;
}) {
  const fontSize = Math.max(Math.min(span * 0.42, 0.22), 0.09);

  return (
    <Text
      position={[0, topY + 0.022, 0]}
      rotation={[-Math.PI / 2, 0, 0]}
      fontSize={fontSize}
      color={isSelected ? '#2a1f0f' : '#1c1c1c'}
      fillOpacity={interactive ? 0.92 : 0.38}
      anchorX="center"
      anchorY="middle"
      outlineWidth={0.012}
      outlineColor="#ffffff"
      outlineOpacity={interactive ? 0.55 : 0.25}
      raycast={() => null}
    >
      {tableDisplayNumber(tableId)}
    </Text>
  );
}

interface TableMeshProps {
  table: SvgTable;
  status: TableStatus;
  isSelected: boolean;
  onTableHover?: (tableId: string | null) => void;
  layer: FloorLayerId;
  interactive: boolean;
}

export const TableMesh = memo(
  function TableMesh({ table, status, isSelected, onTableHover, layer, interactive }: TableMeshProps) {
    const mode = useSceneMode();
    const mobile = mode === 'mobile';
    const topScaleRef = useRef<THREE.Group>(null);
    const [hovered, setHovered] = useState(false);
    const invalidate = useThree((s) => s.invalidate);

    const layout = useMemo(() => computeTableLayout(table), [table]);
    const showRing = interactive && (isSelected || (!mobile && hovered));
    const targetScale = isSelected
      ? mobile
        ? MOBILE_SELECT_SCALE
        : SELECTED_SCALE
      : !mobile && hovered
        ? HOVER_SCALE
        : 1;

    const surfaces =
      table.surfaces.length > 0 ? table.surfaces : [{ shape: 'box' as const, bbox: table.bbox }];

    const labelTopY = FEATURE_BASE_Y + TABLE_LEG_HEIGHT + TABLE_TOP_THICKNESS;
    const labelSpan = Math.max(layout.ringOuter * 2, 0.2);

    const handleHoverChange = useCallback(
      (next: boolean) => {
        setHovered(next);
        onTableHover?.(next ? table.id : null);
      },
      [table.id, onTableHover],
    );

    useFrame((_, delta) => {
      if (!interactive || !topScaleRef.current) return;
      if (targetScale === 1 && Math.abs(topScaleRef.current.scale.x - 1) < 0.001) return;
      const speed = mobile ? MOBILE_ANIMATION_SPEED : ANIMATION_SPEED;
      const next = THREE.MathUtils.lerp(topScaleRef.current.scale.x, targetScale, delta * speed);
      topScaleRef.current.scale.setScalar(next);
      invalidate();
    });

    return (
      <group position={[layout.centerX, 0, layout.centerZ]}>
        <group ref={topScaleRef}>
          {surfaces.map((surface, index) => {
            const [sx, , sz] = svgBBoxCenterToWorld(surface.bbox);
            return (
              <TableTop
                key={`${table.id}-${index}`}
                tableId={table.id}
                shape={surface.shape}
                bbox={surface.bbox}
                localX={sx - layout.centerX}
                localZ={sz - layout.centerZ}
                status={status}
                isSelected={isSelected}
                isHovered={hovered}
                onHoverChange={handleHoverChange}
                layer={layer}
                interactive={interactive}
              />
            );
          })}
        </group>

        {showRing && (
          <SelectionRing
            inner={layout.ringInner}
            outer={layout.ringOuter}
            selected={isSelected}
            mobile={mobile}
          />
        )}

        <TableNumberLabel
          tableId={table.id}
          topY={labelTopY}
          span={labelSpan}
          interactive={interactive}
          isSelected={isSelected}
        />
      </group>
    );
  },
  (prev, next) =>
    prev.status === next.status &&
    prev.isSelected === next.isSelected &&
    prev.table.id === next.table.id &&
    prev.interactive === next.interactive &&
    prev.layer === next.layer,
);

export default TableMesh;
