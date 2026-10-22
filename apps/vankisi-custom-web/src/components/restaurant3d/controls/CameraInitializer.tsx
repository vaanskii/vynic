import { useLayoutEffect } from 'react';
import { useThree } from '@react-three/fiber';
import * as THREE from 'three';

interface CameraInitializerProps {
  position: [number, number, number];
  target: [number, number, number];
  up?: [number, number, number];
}

/** Sync canvas camera to the entrance overview on load / refresh */
export function CameraInitializer({ position, target, up }: CameraInitializerProps) {
  const { camera, invalidate } = useThree();

  useLayoutEffect(() => {
    camera.position.set(position[0], position[1], position[2]);
    if (up) {
      camera.up.set(up[0], up[1], up[2]);
    } else {
      camera.up.set(0, 1, 0);
    }
    camera.lookAt(new THREE.Vector3(target[0], target[1], target[2]));
    if ('fov' in camera) {
      camera.updateProjectionMatrix();
    }
    invalidate();
  }, [camera, position, target, up, invalidate]);

  return null;
}
