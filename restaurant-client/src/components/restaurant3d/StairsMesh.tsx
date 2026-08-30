import {
  FEATURE_BASE_Y,
  FLOOR1_Y,
  STAIR_TREAD_HEIGHT,
  STAIR_TREAD_RISE,
} from './constants';
import { mats } from './materials/sharedMaterials';
import { ghostMaterial } from './materials/ghostMaterials';
import { isMobileDevice } from './utils/performance';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

const RISER_THICKNESS = 0.025;

type StairsVariant = 'ascend' | 'between-floors';

interface StairsMeshProps {
  steps: FloorZone[];
  /** Floor 1 only: rise from local floor. Floor 2: span FLOOR1_Y → FLOOR2_Y in world space. */
  variant?: StairsVariant;
  opacity?: number;
}

function treadTopY(stepIndex: number, variant: StairsVariant): number {
  const riseIndex = stepIndex - 1;
  const base = variant === 'between-floors' ? FLOOR1_Y : FEATURE_BASE_Y;
  return base + riseIndex * STAIR_TREAD_RISE + STAIR_TREAD_HEIGHT;
}

function riserCenterY(stepIndex: number, variant: StairsVariant): number {
  const riseIndex = stepIndex - 1;
  const elevation = riseIndex * STAIR_TREAD_RISE;
  const riserHeight = elevation + STAIR_TREAD_HEIGHT;
  const base = variant === 'between-floors' ? FLOOR1_Y : FEATURE_BASE_Y;
  return base + riserHeight / 2;
}

function StepUnit({
  step,
  variant,
  opacity,
}: {
  step: FloorZone;
  variant: StairsVariant;
  opacity?: number;
}) {
  const stepIndex = step.stepIndex ?? 1;
  const treadTop = treadTopY(stepIndex, variant);

  const { width, depth } = svgBBoxToWorldSize(step.bbox);
  const [x, , z] = svgBBoxCenterToWorld(step.bbox);
  const treadW = Math.max(width, 0.12);
  const treadD = Math.max(depth, 0.12);

  const riseIndex = stepIndex - 1;
  const riserHeight = riseIndex * STAIR_TREAD_RISE + STAIR_TREAD_HEIGHT;
  const riserX = x - treadW / 2 - RISER_THICKNESS / 2;
  const isFirstStep = stepIndex === 1;

  const treadMat =
    opacity !== undefined ? ghostMaterial(mats.stairTread(), opacity, 'ghost-tread') : mats.stairTread();
  const riserMat =
    opacity !== undefined ? ghostMaterial(mats.stairRiser(), opacity, 'ghost-riser') : mats.stairRiser();
  const nosingMat =
    opacity !== undefined ? ghostMaterial(mats.stairNosing(), opacity, 'ghost-nosing') : mats.stairNosing();

  return (
    <group raycast={() => null}>
      {!isFirstStep && (
        <mesh
          position={[riserX, riserCenterY(stepIndex, variant), z]}
        >
          <boxGeometry args={[RISER_THICKNESS, riserHeight, treadD]} />
          <primitive object={riserMat} attach="material" />
        </mesh>
      )}

      <mesh position={[x, treadTop - STAIR_TREAD_HEIGHT / 2, z]}>
        <boxGeometry args={[treadW, STAIR_TREAD_HEIGHT, treadD]} />
        <primitive object={treadMat} attach="material" />
      </mesh>

      <mesh position={[x + treadW * 0.06, treadTop + 0.01, z + treadD * 0.44]}>
        <boxGeometry args={[treadW * 1.02, 0.028, 0.045]} />
        <primitive object={nosingMat} attach="material" />
      </mesh>

      {!isMobileDevice() &&
        [0.5].map((t) => (
          <mesh key={t} position={[x, treadTop + 0.004, z - treadD * 0.35 + treadD * 0.7 * t]}>
            <boxGeometry args={[treadW * 0.88, 0.008, 0.012]} />
            <meshStandardMaterial color="#b8a890" roughness={0.95} />
          </mesh>
        ))}
    </group>
  );
}

export function StairsMesh({ steps, variant = 'ascend', opacity }: StairsMeshProps) {
  if (!steps.length) return null;

  const sorted = [...steps].sort((a, b) => (a.stepIndex ?? 0) - (b.stepIndex ?? 0));

  return (
    <group renderOrder={20} raycast={() => null}>
      {sorted.map((step) => (
        <StepUnit key={step.id} step={step} variant={variant} opacity={opacity} />
      ))}
    </group>
  );
}
