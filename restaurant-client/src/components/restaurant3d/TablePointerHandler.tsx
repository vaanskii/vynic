import { useEffect, useRef } from 'react';
import { useThree } from '@react-three/fiber';
import * as THREE from 'three';
import { TAP_MOVE_THRESHOLD } from './types/sceneMode';

interface TablePointerHandlerProps {
  onTableClick: (tableId: string) => void;
  enabled: boolean;
}

/**
 * Raycast click/tap handler — OrbitControls consumes pointer events before mesh onClick
 * can fire on both touch and desktop.
 */
export function TablePointerHandler({ onTableClick, enabled }: TablePointerHandlerProps) {
  const { camera, scene, gl } = useThree();
  const downRef = useRef<{ x: number; y: number } | null>(null);
  const raycaster = useRef(new THREE.Raycaster());
  const ndc = useRef(new THREE.Vector2());

  useEffect(() => {
    if (!enabled) return undefined;

    const el = gl.domElement;

    const onPointerDown = (e: PointerEvent) => {
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      downRef.current = { x: e.clientX, y: e.clientY };
    };

    const onPointerCancel = () => {
      downRef.current = null;
    };

    const tryPickTable = (clientX: number, clientY: number) => {
      const rect = el.getBoundingClientRect();
      ndc.current.set(
        ((clientX - rect.left) / rect.width) * 2 - 1,
        -((clientY - rect.top) / rect.height) * 2 + 1,
      );

      raycaster.current.setFromCamera(ndc.current, camera);
      const hits = raycaster.current.intersectObjects(scene.children, true);

      for (const hit of hits) {
        let obj: THREE.Object3D | null = hit.object;
        while (obj) {
          const tableId = obj.userData?.tableId as string | undefined;
          if (tableId) {
            onTableClick(tableId);
            return;
          }
          obj = obj.parent;
        }
      }
    };

    const onPointerUp = (e: PointerEvent) => {
      if (!downRef.current) return;
      const dx = e.clientX - downRef.current.x;
      const dy = e.clientY - downRef.current.y;
      downRef.current = null;

      if (Math.hypot(dx, dy) > TAP_MOVE_THRESHOLD) return;

      tryPickTable(e.clientX, e.clientY);
    };

    const onTouchEnd = (e: TouchEvent) => {
      if (!downRef.current || e.changedTouches.length === 0) return;
      const touch = e.changedTouches[0];
      const dx = touch.clientX - downRef.current.x;
      const dy = touch.clientY - downRef.current.y;
      downRef.current = null;

      if (Math.hypot(dx, dy) > TAP_MOVE_THRESHOLD) return;

      e.preventDefault();
      tryPickTable(touch.clientX, touch.clientY);
    };

    const onPointerDownWithTouch = (e: PointerEvent) => {
      onPointerDown(e);
    };

    el.addEventListener('pointerdown', onPointerDownWithTouch, { passive: true });
    el.addEventListener('pointerup', onPointerUp, { passive: true });
    el.addEventListener('pointercancel', onPointerCancel, { passive: true });
    el.addEventListener('touchend', onTouchEnd, { passive: false });
    return () => {
      el.removeEventListener('pointerdown', onPointerDownWithTouch);
      el.removeEventListener('pointerup', onPointerUp);
      el.removeEventListener('pointercancel', onPointerCancel);
      el.removeEventListener('touchend', onTouchEnd);
    };
  }, [enabled, camera, scene, gl, onTableClick]);

  return null;
}
