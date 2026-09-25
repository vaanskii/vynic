import * as THREE from 'three';

const cache = new Map<string, THREE.CanvasTexture>();

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
  ];
}

function surfaceMix(distEdge: number, innerKeep: number): number {
  if (distEdge >= innerKeep) return 1;
  const t = distEdge / innerKeep;
  return t * t * (3 - 2 * t);
}

/**
 * Opaque floor tint: surface color in the center → backdrop at the edges.
 * Avoids alpha holes that reveal layers behind the floor.
 */
export function getFloorSurfaceMap(
  surfaceColor: string,
  backdropColor: string,
  size = 512,
  innerKeep = 0.84,
): THREE.CanvasTexture {
  const key = `${surfaceColor}-${backdropColor}-${size}-${innerKeep}`;
  const hit = cache.get(key);
  if (hit) return hit;

  const [sr, sg, sb] = hexToRgb(surfaceColor);
  const [br, bg, bb] = hexToRgb(backdropColor);

  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  if (!ctx) return new THREE.CanvasTexture(canvas);

  const image = ctx.createImageData(size, size);
  const data = image.data;

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const nx = x / size;
      const ny = y / size;
      const distEdge = Math.min(nx, 1 - nx, ny, 1 - ny) * 2;
      const mix = surfaceMix(distEdge, innerKeep);

      const i = (y * size + x) * 4;
      data[i] = Math.round(br + (sr - br) * mix);
      data[i + 1] = Math.round(bg + (sg - bg) * mix);
      data[i + 2] = Math.round(bb + (sb - bb) * mix);
      data[i + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.needsUpdate = true;
  cache.set(key, texture);
  return texture;
}

/** @deprecated Use getFloorSurfaceMap — alpha fade exposed layers behind the floor */
export function getFloorEdgeFadeMap(size = 512, innerKeep = 0.58): THREE.CanvasTexture {
  return getFloorSurfaceMap('#ffffff', '#000000', size, innerKeep);
}
