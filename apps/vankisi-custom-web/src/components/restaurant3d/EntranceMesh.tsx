import { FEATURE_BASE_Y } from './constants';
import { mats } from './materials/sharedMaterials';
import { layerMaterial, type FloorLayerId } from './materials/ghostMaterials';
import type { FloorZone } from './types';
import { svgPointToWorld, svgSizeToWorld } from './utils/coordinates';

const OUTER_JAMB_SVG_X = 283.517;
const INNER_JAMB_SVG_X = 292.21;
const DOOR_THICKNESS = 0.045;

interface EntranceMeshProps {
  doorways: FloorZone[];
  layer: FloorLayerId;
}

function ClosedDoor({ zone, layer }: { zone: FloorZone; layer: FloorLayerId }) {
  const doorHeight = svgSizeToWorld(zone.bbox.height);
  const midY = zone.bbox.y + zone.bbox.height / 2;

  const [outerX] = svgPointToWorld(OUTER_JAMB_SVG_X, midY);
  const [innerX] = svgPointToWorld(INNER_JAMB_SVG_X, midY);
  const doorX = (outerX + innerX) / 2;

  const [, , zMin] = svgPointToWorld(OUTER_JAMB_SVG_X, zone.bbox.y);
  const [, , zMax] = svgPointToWorld(OUTER_JAMB_SVG_X, zone.bbox.y + zone.bbox.height);
  const depthZ = Math.abs(zMax - zMin);
  const centerZ = (zMin + zMax) / 2;

  const doorMat = layerMaterial(mats.door(), layer, 'geometry');

  return (
    <mesh position={[doorX, FEATURE_BASE_Y + doorHeight / 2, centerZ]}>
      <boxGeometry args={[DOOR_THICKNESS, doorHeight, depthZ]} />
      <primitive object={doorMat} attach="material" />
    </mesh>
  );
}

export function EntranceMesh({ doorways, layer }: EntranceMeshProps) {
  if (!doorways.length) return null;

  return (
    <group renderOrder={15}>
      {doorways.map((zone) => (
        <ClosedDoor key={zone.id} zone={zone} layer={layer} />
      ))}
    </group>
  );
}
