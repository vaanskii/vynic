import { createContext, useContext, type ReactNode } from 'react';
import type { InteractionMode } from '../types/sceneMode';

const SceneModeContext = createContext<InteractionMode>('desktop');

export function SceneModeProvider({
  mode,
  children,
}: {
  mode: InteractionMode;
  children: ReactNode;
}) {
  return <SceneModeContext.Provider value={mode}>{children}</SceneModeContext.Provider>;
}

export function useSceneMode(): InteractionMode {
  return useContext(SceneModeContext);
}
