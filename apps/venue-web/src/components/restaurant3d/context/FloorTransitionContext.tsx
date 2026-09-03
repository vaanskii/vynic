import { createContext, useContext, useEffect, useLayoutEffect, useRef, type ReactNode, type RefObject } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';
import { SCENE_BACKGROUND, FLOOR2_ELEVATION } from '../constants';
import { applyFloorLayerOpacities, setFloorBlendRef } from '../materials/ghostMaterials';
import type { FloorId } from '../types';

const DAMP = 7;

export interface FloorTransitionContextValue {
  blendRef: RefObject<number>;
  cameraElevationRef: RefObject<number>;
  targetFloor: FloorId;
  floor1GroupRef: RefObject<THREE.Group | null>;
  floor2GroupRef: RefObject<THREE.Group | null>;
  isTransitioningRef: RefObject<boolean>;
}

const FloorTransitionContext = createContext<FloorTransitionContextValue | null>(null);

export function useFloorTransition(): FloorTransitionContextValue {
  const ctx = useContext(FloorTransitionContext);
  if (!ctx) {
    throw new Error('useFloorTransition must be used within FloorTransitionProvider');
  }
  return ctx;
}

function FloorTransitionDriver({
  targetFloor,
  blendRef,
  cameraElevationRef,
  floor1GroupRef,
  floor2GroupRef,
  isTransitioningRef,
}: {
  targetFloor: FloorId;
  blendRef: RefObject<number>;
  cameraElevationRef: RefObject<number>;
  floor1GroupRef: RefObject<THREE.Group | null>;
  floor2GroupRef: RefObject<THREE.Group | null>;
  isTransitioningRef: RefObject<boolean>;
}) {
  const invalidate = useThree((s) => s.invalidate);
  const scene = useThree((s) => s.scene);
  const sceneBg = useRef(new THREE.Color(SCENE_BACKGROUND));
  const target = targetFloor === 'floor2' ? 1 : 0;

  const applyOpacities = (blend: number) => {
    applyFloorLayerOpacities(blend, floor1GroupRef.current, floor2GroupRef.current);
  };

  useLayoutEffect(() => {
    applyOpacities(blendRef.current ?? target);
    invalidate();
  }, [targetFloor, target, blendRef, floor1GroupRef, floor2GroupRef, invalidate]);

  useFrame((_, delta) => {
    const current = blendRef.current ?? 0;
    const next = THREE.MathUtils.damp(current, target, DAMP, delta);
    const settled = Math.abs(next - target) < 0.0008;
    const blend = settled ? target : next;

    blendRef.current = blend;
    cameraElevationRef.current = blend * FLOOR2_ELEVATION;
    isTransitioningRef.current = !settled;

    applyOpacities(blend);

    scene.background = sceneBg.current;

    invalidate();
  });

  return null;
}

interface FloorTransitionProviderProps {
  targetFloor: FloorId;
  children: ReactNode;
}

export function FloorTransitionProvider({ targetFloor, children }: FloorTransitionProviderProps) {
  const initial = targetFloor === 'floor2' ? 1 : 0;
  const blendRef = useRef(initial);
  const cameraElevationRef = useRef(initial * FLOOR2_ELEVATION);
  const floor1GroupRef = useRef<THREE.Group | null>(null);
  const floor2GroupRef = useRef<THREE.Group | null>(null);
  const isTransitioningRef = useRef(false);

  useEffect(() => {
    setFloorBlendRef(blendRef);
  }, []);

  const value: FloorTransitionContextValue = {
    blendRef,
    cameraElevationRef,
    targetFloor,
    floor1GroupRef,
    floor2GroupRef,
    isTransitioningRef,
  };

  return (
    <FloorTransitionContext.Provider value={value}>
      <FloorTransitionDriver
        targetFloor={targetFloor}
        blendRef={blendRef}
        cameraElevationRef={cameraElevationRef}
        floor1GroupRef={floor1GroupRef}
        floor2GroupRef={floor2GroupRef}
        isTransitioningRef={isTransitioningRef}
      />
      {children}
    </FloorTransitionContext.Provider>
  );
}
