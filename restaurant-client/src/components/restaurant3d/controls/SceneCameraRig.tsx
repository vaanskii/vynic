import { OrbitControls } from '@react-three/drei';
import { useCallback, useEffect, useLayoutEffect, useRef } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib';
import { CameraInitializer } from './CameraInitializer';
import { useSceneMode } from '../context/SceneModeContext';
import { useFloorTransition } from '../context/FloorTransitionContext';
import {
  getOrbitDistance,
  type DefaultCameraView,
  type TopDownCameraView,
} from '../utils/cameraView';

interface SceneCameraRigProps {
  sceneWidth: number;
  floor1View: DefaultCameraView;
  floor2View: DefaultCameraView;
  /** Floor 1: lock orbit distance; target set once on load — pan/rotate freely after */
  fixedOrbitView?: TopDownCameraView | null;
  onPolarAngleChange?: (polarAngle: number) => void;
}

/** Fixed-distance orbit on both desktop and mobile (touch gestures on mobile) */
export function SceneCameraRig({
  sceneWidth,
  floor1View,
  fixedOrbitView,
  onPolarAngleChange,
}: SceneCameraRigProps) {
  const mobile = useSceneMode() === 'mobile';
  const invalidate = useThree((s) => s.invalidate);
  const camera = useThree((s) => s.camera);
  const { cameraElevationRef } = useFloorTransition();
  const controlsRef = useRef<OrbitControlsImpl>(null);
  const prevElevationRef = useRef(cameraElevationRef.current ?? 0);
  const orbitDistance = getOrbitDistance(sceneWidth, mobile);

  const lockedDistance = fixedOrbitView?.distance ?? orbitDistance;
  const lockedTarget = fixedOrbitView?.target ?? floor1View.target;
  // Desktop: allow zoom within a range around the default distance. Mobile: stay locked.
  const minDistance = mobile ? lockedDistance : lockedDistance * 0.4;
  const maxDistance = mobile ? lockedDistance : lockedDistance * 1.6;
  const orbitSetupKey = `${lockedTarget[0]},${lockedTarget[1]},${lockedTarget[2]},${lockedDistance}`;

  const reportPolarAngle = useCallback(() => {
    const polar = controlsRef.current?.getPolarAngle();
    if (polar !== undefined) {
      onPolarAngleChange?.(polar);
    }
  }, [onPolarAngleChange]);

  const handleChange = useCallback(() => {
    invalidate();
    reportPolarAngle();
  }, [invalidate, reportPolarAngle]);

  useEffect(() => {
    reportPolarAngle();
  }, [reportPolarAngle]);

  /** Keep the orbit target locked to the floor and shift it during floor transitions */
  useFrame(() => {
    const cameraElevation = cameraElevationRef.current ?? 0;
    const delta = cameraElevation - prevElevationRef.current;
    if (Math.abs(delta) < 1e-6) return;

    camera.position.y += delta;
    const controls = controlsRef.current;
    if (controls) {
      controls.target.y += delta;
    }

    prevElevationRef.current = cameraElevation;
    invalidate();
  });

  /** Set orbit target + distance once per floor */
  useLayoutEffect(() => {
    const controls = controlsRef.current;
    if (!controls) return;
    controls.target.set(lockedTarget[0], lockedTarget[1], lockedTarget[2]);
    controls.minDistance = minDistance;
    controls.maxDistance = maxDistance;
    controls.update();
    invalidate();
  }, [orbitSetupKey, lockedTarget, minDistance, maxDistance, invalidate]);

  return (
    <>
      <CameraInitializer position={floor1View.position} target={lockedTarget} />

      <OrbitControls
        ref={controlsRef}
        enablePan
        enableZoom={!mobile}
        enableRotate
        rotateSpeed={mobile ? 0.7 : 1}
        zoomSpeed={0.9}
        minPolarAngle={0.04}
        maxPolarAngle={Math.PI / 2.05}
        minDistance={minDistance}
        maxDistance={maxDistance}
        onChange={handleChange}
        mouseButtons={{
          LEFT: THREE.MOUSE.ROTATE,
          MIDDLE: THREE.MOUSE.PAN,
          RIGHT: THREE.MOUSE.PAN,
        }}
        touches={{
          ONE: THREE.TOUCH.ROTATE,
          TWO: THREE.TOUCH.PAN,
        }}
      />
    </>
  );
}
