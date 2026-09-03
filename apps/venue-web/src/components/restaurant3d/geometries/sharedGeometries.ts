import * as THREE from 'three';
import { getCylinderSegments } from '../utils/performance';

let segments = getCylinderSegments();

export function refreshGeometrySegments(): void {
  segments = getCylinderSegments();
  _tableLeg = null;
  _pole = null;
  _roundTop = null;
}

let _tableLeg: THREE.CylinderGeometry | null = null;
export function tableLegGeometry(legH: number): THREE.CylinderGeometry {
  if (!_tableLeg) _tableLeg = new THREE.CylinderGeometry(0.018, 0.016, legH, segments);
  return _tableLeg;
}

let _pole: THREE.CylinderGeometry | null = null;
export function poleGeometry(h: number, radius: number): THREE.CylinderGeometry {
  if (!_pole) _pole = new THREE.CylinderGeometry(radius, radius, h, segments);
  return _pole;
}

let _roundTop: THREE.CylinderGeometry | null = null;
export function roundTableTopGeometry(thickness: number, radius: number): THREE.CylinderGeometry {
  if (!_roundTop) _roundTop = new THREE.CylinderGeometry(radius, radius, thickness, segments + 4);
  return _roundTop;
}

export const boxTableTop = (w: number, t: number, d: number) => new THREE.BoxGeometry(w, t, d);
