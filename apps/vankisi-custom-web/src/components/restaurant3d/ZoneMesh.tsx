import {
  BAR_COUNTER_HEIGHT,
  FEATURE_BASE_Y,
  STAGE_PLATFORM_HEIGHT,
} from './constants';
import { mats } from './materials/sharedMaterials';
import { layerMaterial, type FloorLayerId } from './materials/ghostMaterials';
import type { FloorZone } from './types';
import { svgBBoxCenterToWorld, svgBBoxToWorldSize } from './utils/coordinates';

interface ZoneMeshProps {
  zone: FloorZone;
  layer: FloorLayerId;
}

function BarCounter({
  x,
  z,
  width,
  depth,
  layer,
}: {
  x: number;
  z: number;
  width: number;
  depth: number;
  layer: FloorLayerId;
}) {
  const h = BAR_COUNTER_HEIGHT;
  const bodyH = h * 0.72;
  const topH = h * 0.14;
  const bodyMat = layerMaterial(mats.barBody(), layer, 'geometry');
  const topMat = layerMaterial(mats.barTop(), layer, 'geometry');

  return (
    <group position={[x, 0, z]} raycast={() => null}>
      <mesh position={[0, FEATURE_BASE_Y + bodyH / 2, 0]}>
        <boxGeometry args={[width, bodyH, depth]} />
        <primitive object={bodyMat} attach="material" />
      </mesh>
      <mesh position={[0, FEATURE_BASE_Y + bodyH + topH / 2 + 0.01, 0]}>
        <boxGeometry args={[width * 1.03, topH, depth * 1.04]} />
        <primitive object={topMat} attach="material" />
      </mesh>
    </group>
  );
}

function StagePlatform({
  x,
  z,
  width,
  depth,
  layer,
}: {
  x: number;
  z: number;
  width: number;
  depth: number;
  layer: FloorLayerId;
}) {
  const h = STAGE_PLATFORM_HEIGHT;
  const stageMat = layerMaterial(mats.stage(), layer, 'geometry');
  const lipMat = layerMaterial(mats.stageLip(), layer, 'geometry');

  return (
    <group position={[x, 0, z]} raycast={() => null}>
      <mesh position={[0, FEATURE_BASE_Y + h / 2, 0]}>
        <boxGeometry args={[width, h, depth]} />
        <primitive object={stageMat} attach="material" />
      </mesh>
      <mesh position={[0, FEATURE_BASE_Y + h + 0.03, depth * 0.46]}>
        <boxGeometry args={[width, 0.07, 0.08]} />
        <primitive object={lipMat} attach="material" />
      </mesh>
    </group>
  );
}

export function ZoneMesh({ zone, layer }: ZoneMeshProps) {
  const { width, depth } = svgBBoxToWorldSize(zone.bbox);
  const [x, , z] = svgBBoxCenterToWorld(zone.bbox);

  if (width < 0.015 && depth < 0.015) return null;

  if (zone.kind === 'bar') {
    return (
      <BarCounter
        x={x}
        z={z}
        width={Math.max(width, 0.12)}
        depth={Math.max(depth, 0.12)}
        layer={layer}
      />
    );
  }

  if (zone.kind === 'stage') {
    return (
      <StagePlatform x={x} z={z} width={width} depth={depth} layer={layer} />
    );
  }

  return null;
}
