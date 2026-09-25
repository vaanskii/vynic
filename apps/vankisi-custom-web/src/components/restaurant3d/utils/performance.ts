/** Mobile / GPU tier helpers for adaptive 3D quality */

export function isMobileDevice(): boolean {
  if (typeof window === 'undefined') return false;
  return (
    window.matchMedia('(max-width: 768px)').matches ||
    window.matchMedia('(pointer: coarse)').matches
  );
}

export function getAdaptiveDpr(): [number, number] {
  return isMobileDevice() ? [1, 1.5] : [1, 2];
}

export function getCylinderSegments(): number {
  return isMobileDevice() ? 8 : 12;
}

export function getFloorTextureMaxSize(): number {
  return isMobileDevice() ? 1024 : 2048;
}

export function shouldUseAntialias(): boolean {
  return !isMobileDevice();
}
