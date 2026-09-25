import { BAR_COUNTER_HEIGHT, FEATURE_BASE_Y } from './constants';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

const BOTTLE_COLORS = ['#2d5a2d', '#5a2d2d', '#8a6a2a', '#2a4a6a', '#4a2a5a', '#6a4a2a'];

/** Top bar run flush against the north exterior wall — only segment with bottle shelf */
const BAR_WALL_SEGMENT_ID = 'bar-path1042_2';

interface BarDetailMeshProps {
  barZones: FloorZone[];
}

function Bottle({ x, y, z, height, color }: { x: number; y: number; z: number; height: number; color: string }) {
  const radius = 0.018;
  return (
    <group position={[x, y, z]}>
      <mesh position={[0, height / 2, 0]}>
        <cylinderGeometry args={[radius * 0.7, radius, height, 8]} />
        <meshStandardMaterial color={color} roughness={0.28} metalness={0.15} transparent opacity={0.92} />
      </mesh>
      <mesh position={[0, height + 0.012, 0]}>
        <cylinderGeometry args={[radius * 0.35, radius * 0.4, 0.03, 8]} />
        <meshStandardMaterial color="#6a6058" roughness={0.5} metalness={0.2} />
      </mesh>
    </group>
  );
}

function BarBackWall({ zone }: { zone: FloorZone }) {
  const { width, depth } = svgBBoxToWorldSize(zone.bbox);
  const [x, , z] = svgBBoxCenterToWorld(zone.bbox);

  const bodyH = BAR_COUNTER_HEIGHT * 0.72;
  const topH = BAR_COUNTER_HEIGHT * 0.14;
  const shelfY = FEATURE_BASE_Y + bodyH + topH;
  const wallH = 0.52;
  const wallT = 0.06;
  const wallWidth = width + 0.04;
  const wallZ = z - depth / 2 - wallT / 2 - 0.02;

  const bottleCount = Math.max(5, Math.min(14, Math.floor(width / 0.08)));

  return (
    <group>
      <mesh position={[x, shelfY + wallH / 2, wallZ]}>
        <boxGeometry args={[wallWidth, wallH, wallT]} />
        <meshStandardMaterial color="#2a1e14" roughness={0.75} metalness={0.05} />
      </mesh>

      <mesh position={[x, shelfY + 0.04, wallZ]}>
        <boxGeometry args={[wallWidth * 0.96, 0.035, wallT * 1.3]} />
        <meshStandardMaterial color="#4a3828" roughness={0.55} metalness={0.12} />
      </mesh>

      <mesh position={[x, shelfY + wallH * 0.55, wallZ - wallT * 0.35]}>
        <boxGeometry args={[wallWidth * 0.9, wallH * 0.7, 0.01]} />
        <meshStandardMaterial color="#1a2838" emissive="#2a4060" emissiveIntensity={0.25} roughness={0.15} metalness={0.6} />
      </mesh>

      {Array.from({ length: bottleCount }, (_, i) => {
        const t = (i + 0.5) / bottleCount;
        const h = 0.14 + (i % 3) * 0.03;
        return (
          <Bottle
            key={i}
            x={x - width / 2 + width * t}
            y={shelfY + 0.06}
            z={wallZ}
            height={h}
            color={BOTTLE_COLORS[i % BOTTLE_COLORS.length]}
          />
        );
      })}
    </group>
  );
}

export function BarDetailMesh({ barZones }: BarDetailMeshProps) {
  const wallSegment = barZones.find((z) => z.id === BAR_WALL_SEGMENT_ID);
  if (!wallSegment) return null;

  return (
    <group renderOrder={12}>
      <BarBackWall zone={wallSegment} />
    </group>
  );
}
