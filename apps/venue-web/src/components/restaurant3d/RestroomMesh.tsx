import { useMemo } from 'react';
import { Text } from '@react-three/drei';
import * as THREE from 'three';
import { FEATURE_BASE_Y } from './constants';
import {
  registerLayerMaterial,
  type FloorLayerId,
} from './materials/ghostMaterials';
import type { RestroomGender, RestroomUnit, SvgBBox } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize, svgPointToWorld } from './utils/coordinates';

const FLOOR_Y = FEATURE_BASE_Y + 0.003;
const TOILET_YAW = 0;

const WC_THEME: Record<
  RestroomGender,
  { floor: string; accent: string; sign: string; symbol: string }
> = {
  man: { floor: '#c8d4e4', accent: '#4a6f9c', sign: '#3d628f', symbol: '♂' },
  woman: { floor: '#e4d0dc', accent: '#a85f7d', sign: '#944f6b', symbol: '♀' },
};

function layerColorMat(color: string, layer: FloorLayerId, roughness = 0.5): THREE.MeshStandardMaterial {
  return registerLayerMaterial(
    new THREE.MeshStandardMaterial({ color, roughness, metalness: 0.04 }),
    layer,
    'geometry',
  );
}

function BathPad({ bath, color, layer }: { bath: SvgBBox; color: string; layer: FloorLayerId }) {
  const { width, depth } = svgBBoxToWorldSize(bath);
  const [x, , z] = svgBBoxCenterToWorld(bath);
  const mat = useMemo(() => layerColorMat(color, layer, 0.75), [color, layer]);

  return (
    <mesh
      position={[x, FLOOR_Y + 0.001, z]}
      rotation={[-Math.PI / 2, 0, 0]}
      material={mat}
      raycast={() => null}
    >
      <planeGeometry args={[width * 0.98, depth * 0.98]} />
    </mesh>
  );
}

function bathCenter(bath: SvgBBox): [number, number] {
  return [bath.x + bath.width / 2, bath.y + bath.height / 2];
}

function Toilet({ x, z, layer }: { x: number; z: number; layer: FloorLayerId }) {
  const porcelain = useMemo(
    () => layerColorMat('#eceae6', layer, 0.32),
    [layer],
  );
  const seat = useMemo(
    () => layerColorMat('#f6f5f3', layer, 0.28),
    [layer],
  );

  return (
    <group position={[x, FLOOR_Y, z]} rotation={[0, TOILET_YAW, 0]} raycast={() => null}>
      <mesh position={[0, 0.1, 0.07]} material={porcelain}>
        <cylinderGeometry args={[0.095, 0.08, 0.13, 20]} />
      </mesh>
      <mesh position={[0, 0.18, -0.11]} material={porcelain}>
        <boxGeometry args={[0.19, 0.26, 0.085]} />
      </mesh>
      <mesh position={[0, 0.2, 0.07]} rotation={[Math.PI / 2, 0, 0]} material={seat}>
        <torusGeometry args={[0.09, 0.016, 10, 24]} />
      </mesh>
    </group>
  );
}

function StallFloor({
  stall,
  color,
  layer,
}: {
  stall: SvgBBox;
  color: string;
  layer: FloorLayerId;
}) {
  const { width, depth } = svgBBoxToWorldSize(stall);
  const [x, , z] = svgBBoxCenterToWorld(stall);
  const mat = useMemo(() => layerColorMat(color, layer, 0.88), [color, layer]);

  if (width < 0.05 || depth < 0.05) return null;

  return (
    <mesh
      position={[x, FLOOR_Y, z]}
      rotation={[-Math.PI / 2, 0, 0]}
      material={mat}
      raycast={() => null}
    >
      <planeGeometry args={[width * 0.94, depth * 0.94]} />
    </mesh>
  );
}

function GenderSign({
  gender,
  x,
  z,
  layer,
}: {
  gender: RestroomGender;
  x: number;
  z: number;
  layer: FloorLayerId;
}) {
  const theme = WC_THEME[gender];
  const signMat = useMemo(() => layerColorMat(theme.sign, layer, 0.45), [theme.sign, layer]);

  return (
    <group position={[x, FEATURE_BASE_Y + 0.34, z]} raycast={() => null}>
      <mesh material={signMat}>
        <boxGeometry args={[0.28, 0.36, 0.03]} />
      </mesh>
      <Text
        position={[0, 0, 0.02]}
        fontSize={0.18}
        color="#f5f8fc"
        anchorX="center"
        anchorY="middle"
        raycast={() => null}
      >
        {theme.symbol}
      </Text>
    </group>
  );
}

function RestroomUnitMesh({ unit, layer }: { unit: RestroomUnit; layer: FloorLayerId }) {
  const theme = WC_THEME[unit.gender];
  const signX = unit.bounds.x + unit.bounds.width / 2;
  const signY = unit.bounds.y + unit.bounds.height + 6;

  return (
    <group raycast={() => null}>
      {unit.stalls.map((stall) => (
        <StallFloor key={stall.id} stall={stall.bbox} color={theme.floor} layer={layer} />
      ))}
      {unit.stalls.map(
        (stall) =>
          stall.bathBBox && (
            <BathPad key={`${stall.id}-bath`} bath={stall.bathBBox} color={theme.accent} layer={layer} />
          ),
      )}
      {unit.stalls.map((stall) => {
        const target = stall.bathBBox ?? stall.bbox;
        const [sx, sy] = stall.bathBBox
          ? bathCenter(stall.bathBBox)
          : [target.x + target.width / 2, target.y + target.height * 0.68];
        const [x, , z] = svgPointToWorld(sx, sy);
        return <Toilet key={`${stall.id}-toilet`} x={x} z={z} layer={layer} />;
      })}
      {(() => {
        const [x, , z] = svgPointToWorld(signX, signY);
        return <GenderSign gender={unit.gender} x={x} z={z} layer={layer} />;
      })()}
    </group>
  );
}

interface RestroomMeshProps {
  restrooms: RestroomUnit[];
  layer: FloorLayerId;
}

export function RestroomMesh({ restrooms, layer }: RestroomMeshProps) {
  if (!restrooms.length) return null;

  return (
    <group raycast={() => null}>
      {restrooms.map((unit) => (
        <RestroomUnitMesh key={unit.id} unit={unit} layer={layer} />
      ))}
    </group>
  );
}
