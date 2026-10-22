import * as THREE from 'three';
import {
  FLOOR_SURFACE,
  FLOOR_SURFACE_FLOOR2,
  SELECTED_COLOR,
  SELECTED_EMISSIVE,
  STATUS_COLORS,
  STATUS_EMISSIVE,
  ZONE_COLORS,
  ZONE_EMISSIVE,
} from '../constants';
import type { TableStatus } from '../types';

/** Module-level material pool — one GPU material per visual role */
const cache = new Map<string, THREE.MeshStandardMaterial>();

function mat(key: string, props: THREE.MeshStandardMaterialParameters): THREE.MeshStandardMaterial {
  let m = cache.get(key);
  if (!m) {
    m = new THREE.MeshStandardMaterial(props);
    cache.set(key, m);
  }
  return m;
}

export const mats = {
  floorSlab: () => mat('floorSlab', { color: FLOOR_SURFACE, roughness: 0.96, metalness: 0.02 }),
  floorSlabFloor2: () =>
    mat('floorSlabFloor2', { color: FLOOR_SURFACE_FLOOR2, roughness: 0.92, metalness: 0.04 }),
  floorPlan: () => mat('floorPlan', { roughness: 0.88, metalness: 0.03 }),
  tableEdge: () => mat('tableEdge', { color: '#5c4a38', roughness: 0.45, metalness: 0.2 }),
  chairSeat: () => mat('chairSeat', { color: '#3d3530', roughness: 0.72, metalness: 0.04 }),
  chairWood: () => mat('chairWood', { color: '#3a3028', roughness: 0.65, metalness: 0.05 }),
  wall: () =>
    mat('wall', {
      color: ZONE_COLORS.wall,
      emissive: ZONE_EMISSIVE.wall,
      emissiveIntensity: 0.05,
      roughness: 0.7,
      metalness: 0.05,
    }),
  structure: () =>
    mat('structure', {
      color: ZONE_COLORS.structure,
      emissive: ZONE_EMISSIVE.structure,
      emissiveIntensity: 0.05,
      roughness: 0.7,
      metalness: 0.05,
    }),
  barBody: () =>
    mat('barBody', { color: '#f0eeea', roughness: 0.38, metalness: 0.08 }),
  barTop: () =>
    mat('barTop', { color: '#ffffff', roughness: 0.18, metalness: 0.12 }),
  stage: () =>
    mat('stage', {
      color: ZONE_COLORS.stage,
      emissive: ZONE_EMISSIVE.stage,
      emissiveIntensity: 0.3,
      roughness: 0.28,
      metalness: 0.18,
    }),
  stageLip: () =>
    mat('stageLip', {
      color: '#2a2018',
      emissive: '#a89763',
      emissiveIntensity: 0.2,
      roughness: 0.32,
      metalness: 0.22,
    }),
  pole: () =>
    mat('pole', {
      color: ZONE_COLORS.pole,
      roughness: 0.4,
      metalness: 0.25,
    }),
  stairTread: () =>
    mat('stairTread', {
      color: '#d4c4a8',
      emissive: '#9a8870',
      emissiveIntensity: 0.15,
      roughness: 0.42,
      metalness: 0.06,
    }),
  stairRiser: () => mat('stairRiser', { color: '#4a433c', roughness: 0.9, metalness: 0.03 }),
  stairNosing: () => mat('stairNosing', { color: '#ece2d4', roughness: 0.32, metalness: 0.08 }),
  stairStringer: () => mat('stairStringer', { color: '#3d3832', roughness: 0.85, metalness: 0.05 }),
  stairLanding: () => mat('stairLanding', { color: '#9a9080', roughness: 0.72, metalness: 0.03 }),
  door: () => mat('door', { color: '#e8dcc8', roughness: 0.42, metalness: 0.08 }),
  entranceWood: () => mat('entranceWood', { color: '#ebe3d4', roughness: 0.4, metalness: 0.1 }),
  glassWall: () =>
    mat('glassWall', {
      color: '#e8d0de',
      emissive: '#c8a0b8',
      emissiveIntensity: 0.28,
      roughness: 0.12,
      metalness: 0.15,
      transparent: true,
      opacity: 0.58,
      side: THREE.DoubleSide,
    }),
  photoZone: () =>
    mat('photoZone', {
      color: ZONE_COLORS['photo-zone'],
      emissive: ZONE_EMISSIVE['photo-zone'],
      emissiveIntensity: 0.35,
      roughness: 0.55,
      metalness: 0.12,
    }),
  railing: () =>
    mat('railing', {
      color: ZONE_COLORS.railing,
      roughness: 0.35,
      metalness: 0.45,
    }),
};

const statusMatCache = new Map<string, THREE.MeshStandardMaterial>();

export function getStatusMaterial(
  status: TableStatus,
  highlighted = false,
  mobile = false,
  selected = false,
): THREE.MeshStandardMaterial {
  const key = `${status}-${selected ? 'sel' : highlighted ? 'hi' : 'lo'}-${mobile ? 'm' : 'd'}`;
  let m = statusMatCache.get(key);
  if (!m) {
    m = new THREE.MeshStandardMaterial({
      color: selected ? SELECTED_COLOR : STATUS_COLORS[status],
      emissive: selected ? SELECTED_EMISSIVE : STATUS_EMISSIVE[status],
      emissiveIntensity: selected
        ? mobile
          ? 0.78
          : 0.62
        : mobile
          ? highlighted
            ? 0.72
            : 0.58
          : highlighted
            ? 0.48
            : 0.32,
      roughness: selected || highlighted ? 0.22 : 0.32,
      metalness: selected || highlighted ? 0.35 : 0.2,
    });
    statusMatCache.set(key, m);
  }
  return m;
}
