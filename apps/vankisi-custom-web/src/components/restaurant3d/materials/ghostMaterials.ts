import type { RefObject } from 'react';
import * as THREE from 'three';
import {
  FLOOR1_GHOST_OPACITY,
  FLOOR1_GHOST_TABLE_OPACITY,
  FLOOR2_GHOST_OPACITY,
  FLOOR2_GHOST_TABLE_OPACITY,
} from '../constants';

export type FloorLayerId = 'floor1' | 'floor2';
export type LayerMaterialRole = 'geometry' | 'table' | 'floor';

const layerMaterialCache = new Map<string, THREE.MeshStandardMaterial>();
const registeredMaterials = new Set<THREE.MeshStandardMaterial>();

let blendRef: RefObject<number> | null = null;
let fallbackBlend = 0;

/** Wired once by FloorTransitionProvider */
export function setFloorBlendRef(ref: RefObject<number>): void {
  blendRef = ref;
}

function getBlend(): number {
  return blendRef?.current ?? fallbackBlend;
}

export function geometryOpacityForLayer(layer: FloorLayerId, blend: number): number {
  if (layer === 'floor1') {
    if (blend <= 0.001) return 1;
    if (blend >= 0.999) return FLOOR1_GHOST_OPACITY;
    return THREE.MathUtils.lerp(1, FLOOR1_GHOST_OPACITY, blend);
  }
  if (blend >= 0.999) return 1;
  if (blend <= 0.001) return FLOOR2_GHOST_OPACITY;
  return THREE.MathUtils.lerp(FLOOR2_GHOST_OPACITY, 1, blend);
}

export function tableOpacityForLayer(layer: FloorLayerId, blend: number): number {
  if (layer === 'floor1') {
    if (blend <= 0.001) return 1;
    if (blend >= 0.999) return FLOOR1_GHOST_TABLE_OPACITY;
    return THREE.MathUtils.lerp(1, FLOOR1_GHOST_TABLE_OPACITY, blend);
  }
  if (blend >= 0.999) return 1;
  if (blend <= 0.001) return FLOOR2_GHOST_TABLE_OPACITY;
  return THREE.MathUtils.lerp(FLOOR2_GHOST_TABLE_OPACITY, 1, blend);
}

function targetOpacityForMaterial(
  material: THREE.MeshStandardMaterial,
  blend: number,
): number {
  const layer = material.userData.floorLayer as FloorLayerId;
  const role = (material.userData.layerRole as LayerMaterialRole) ?? 'geometry';
  return role === 'table'
    ? tableOpacityForLayer(layer, blend)
    : geometryOpacityForLayer(layer, blend);
}

function applyMaterialOpacity(material: THREE.MeshStandardMaterial, opacity: number): void {
  if (material.userData.baseEmissiveIntensity === undefined) {
    material.userData.baseEmissiveIntensity = material.emissiveIntensity ?? 0;
  }
  material.opacity = opacity;
  material.transparent = opacity < 0.999;
  material.depthWrite = opacity >= 0.92;
  material.needsUpdate = true;
  const base = material.userData.baseEmissiveIntensity as number;
  material.emissiveIntensity = opacity < 0.999 ? base * opacity * 0.35 : base;
}

function trackMaterial(material: THREE.MeshStandardMaterial): void {
  registeredMaterials.add(material);
}

/** Sync one layer-managed material to the given blend */
export function syncLayerMaterialOpacity(
  material: THREE.MeshStandardMaterial,
  blend = getBlend(),
): void {
  if (!material.userData.layerManaged) return;
  applyMaterialOpacity(material, targetOpacityForMaterial(material, blend));
}

/** Mark an ad-hoc material (e.g. restroom props) as layer-managed */
export function registerLayerMaterial(
  material: THREE.MeshStandardMaterial,
  layer: FloorLayerId,
  role: LayerMaterialRole = 'geometry',
): THREE.MeshStandardMaterial {
  material.userData.floorLayer = layer;
  material.userData.layerRole = role;
  material.userData.layerManaged = true;
  trackMaterial(material);
  return material;
}

/** Stable per-layer material clone — opacity applied via syncAllLayerMaterials */
export function layerMaterial(
  base: THREE.MeshStandardMaterial,
  layer: FloorLayerId,
  role: LayerMaterialRole,
): THREE.MeshStandardMaterial {
  const key = `${layer}:${role}:${base.uuid}`;
  let material = layerMaterialCache.get(key);
  if (!material) {
    material = base.clone();
    material.userData.floorLayer = layer;
    material.userData.layerRole = role;
    material.userData.layerManaged = true;
    material.transparent = true;
    layerMaterialCache.set(key, material);
    trackMaterial(material);
  }
  return material;
}

function syncMeshesInGroup(group: THREE.Group | null, layer: FloorLayerId, blend: number): void {
  if (!group) return;

  group.traverse((obj) => {
    if (!(obj instanceof THREE.Mesh)) return;
    const materials = Array.isArray(obj.material) ? obj.material : [obj.material];
    materials.forEach((material) => {
      if (!(material instanceof THREE.MeshStandardMaterial)) return;
      if (!material.userData.layerManaged || material.userData.floorLayer !== layer) return;
      trackMaterial(material);
      syncLayerMaterialOpacity(material, blend);
    });
  });
}

/** Push blend to every layer-managed material in the scene */
export function syncAllLayerMaterials(blend: number): void {
  fallbackBlend = blend;

  for (const material of registeredMaterials) {
    if (material.userData.layerManaged) {
      syncLayerMaterialOpacity(material, blend);
    }
  }
}

export function applyFloorLayerOpacities(
  blend: number,
  floor1Group: THREE.Group | null,
  floor2Group: THREE.Group | null,
): void {
  syncAllLayerMaterials(blend);
  syncMeshesInGroup(floor1Group, 'floor1', blend);
  syncMeshesInGroup(floor2Group, 'floor2', blend);
}

/** @deprecated Use layerMaterial — kept for legacy ghost layers */
export function ghostMaterial(
  base: THREE.MeshStandardMaterial,
  opacity: number,
  key: string,
): THREE.MeshStandardMaterial {
  let material = layerMaterialCache.get(`legacy:${key}`);
  if (!material) {
    material = base.clone();
    material.transparent = true;
    material.depthWrite = false;
    material.roughness = Math.min(1, material.roughness + 0.18);
    layerMaterialCache.set(`legacy:${key}`, material);
  }
  applyMaterialOpacity(material, opacity);
  return material;
}
