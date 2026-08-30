import { useEffect } from 'react';
import { useThree } from '@react-three/fiber';

/** Request a frame when frameloop="demand" */
export function useSceneInvalidate(deps: unknown[] = []): () => void {
  const invalidate = useThree((s) => s.invalidate);

  useEffect(() => {
    invalidate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return invalidate;
}
