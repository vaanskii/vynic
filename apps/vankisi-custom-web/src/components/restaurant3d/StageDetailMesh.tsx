import { FEATURE_BASE_Y, STAGE_PLATFORM_HEIGHT } from './constants';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

interface StageDetailMeshProps {
  stageZone?: FloorZone;
}

function DrumKit({ x, y, z }: { x: number; y: number; z: number }) {
  return (
    <group position={[x, y, z]}>
      <mesh position={[0, 0.06, 0]}>
        <cylinderGeometry args={[0.14, 0.14, 0.1, 20]} />
        <meshStandardMaterial color="#e8e8e8" roughness={0.35} metalness={0.55} />
      </mesh>
      <mesh position={[-0.16, 0.05, 0.08]} rotation={[0.2, 0, 0.15]}>
        <cylinderGeometry args={[0.1, 0.1, 0.07, 18]} />
        <meshStandardMaterial color="#d0d0d0" roughness={0.38} metalness={0.5} />
      </mesh>
      <mesh position={[0.16, 0.05, 0.08]} rotation={[0.2, 0, -0.15]}>
        <cylinderGeometry args={[0.09, 0.09, 0.065, 18]} />
        <meshStandardMaterial color="#d0d0d0" roughness={0.38} metalness={0.5} />
      </mesh>
      <mesh position={[0, 0.14, -0.1]}>
        <cylinderGeometry args={[0.05, 0.05, 0.22, 12]} />
        <meshStandardMaterial color="#888" roughness={0.4} metalness={0.6} />
      </mesh>
    </group>
  );
}

function MicStand({ x, y, z }: { x: number; y: number; z: number }) {
  return (
    <group position={[x, y, z]}>
      <mesh position={[0, 0.2, 0]}>
        <cylinderGeometry args={[0.008, 0.012, 0.4, 8]} />
        <meshStandardMaterial color="#333" roughness={0.3} metalness={0.7} />
      </mesh>
      <mesh position={[0, 0.42, 0]}>
        <sphereGeometry args={[0.025, 10, 10]} />
        <meshStandardMaterial color="#222" roughness={0.25} metalness={0.8} />
      </mesh>
      <mesh position={[0, 0.01, 0]}>
        <cylinderGeometry args={[0.1, 0.12, 0.02, 16]} />
        <meshStandardMaterial color="#222" roughness={0.5} metalness={0.5} />
      </mesh>
    </group>
  );
}

function Guitar({ x, y, z, rotationY = 0 }: { x: number; y: number; z: number; rotationY?: number }) {
  return (
    <group position={[x, y, z]} rotation={[0.15, rotationY, 0]}>
      <mesh position={[0, 0.04, 0]}>
        <boxGeometry args={[0.14, 0.04, 0.38]} />
        <meshStandardMaterial color="#8b2020" roughness={0.45} metalness={0.15} />
      </mesh>
      <mesh position={[0, 0.06, -0.26]}>
        <boxGeometry args={[0.05, 0.03, 0.14]} />
        <meshStandardMaterial color="#5a1818" roughness={0.5} metalness={0.1} />
      </mesh>
      <mesh position={[0, 0.1, -0.34]}>
        <cylinderGeometry args={[0.012, 0.015, 0.12, 8]} />
        <meshStandardMaterial color="#3a2818" roughness={0.6} metalness={0.05} />
      </mesh>
    </group>
  );
}

function Keyboard({ x, y, z }: { x: number; y: number; z: number }) {
  return (
    <group position={[x, y, z]}>
      <mesh position={[0, 0.03, 0]}>
        <boxGeometry args={[0.5, 0.06, 0.18]} />
        <meshStandardMaterial color="#1a1a1a" roughness={0.35} metalness={0.2} />
      </mesh>
      <mesh position={[0, 0.065, 0]}>
        <boxGeometry args={[0.46, 0.01, 0.14]} />
        <meshStandardMaterial color="#f0f0f0" roughness={0.5} metalness={0.05} />
      </mesh>
    </group>
  );
}

export function StageDetailMesh({ stageZone }: StageDetailMeshProps) {
  if (!stageZone) return null;

  const { width, depth } = svgBBoxToWorldSize(stageZone.bbox);
  const [x, , z] = svgBBoxCenterToWorld(stageZone.bbox);
  const topY = FEATURE_BASE_Y + STAGE_PLATFORM_HEIGHT;

  return (
    <group renderOrder={12}>
      <DrumKit x={x + width * 0.18} y={topY} z={z + depth * 0.12} />
      <MicStand x={x - width * 0.1} y={topY} z={z - depth * 0.15} />
      <Guitar x={x - width * 0.25} y={topY} z={z + depth * 0.2} rotationY={0.4} />
      <Guitar x={x + width * 0.28} y={topY} z={z - depth * 0.05} rotationY={-0.5} />
      <Keyboard x={x} y={topY} z={z - depth * 0.28} />
    </group>
  );
}
