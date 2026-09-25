import { useEffect, useState } from 'react';
import type { InteractionMode } from '../types/sceneMode';
import { isMobileDevice } from '../utils/performance';

export function useInteractionMode(): InteractionMode {
  const [mode, setMode] = useState<InteractionMode>(() =>
    typeof window !== 'undefined' && isMobileDevice() ? 'mobile' : 'desktop',
  );

  useEffect(() => {
    const mobileMq = window.matchMedia('(max-width: 768px)');
    const coarseMq = window.matchMedia('(pointer: coarse)');

    const sync = () => {
      setMode(mobileMq.matches || coarseMq.matches ? 'mobile' : 'desktop');
    };

    sync();
    mobileMq.addEventListener('change', sync);
    coarseMq.addEventListener('change', sync);
    return () => {
      mobileMq.removeEventListener('change', sync);
      coarseMq.removeEventListener('change', sync);
    };
  }, []);

  return mode;
}
