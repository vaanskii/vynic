import { useSceneMode } from './context/SceneModeContext';
import { SCENE_BACKGROUND } from './constants';

interface SceneLightingProps {
  sceneWidth: number;
}

export function SceneLighting({ sceneWidth }: SceneLightingProps) {
  const mode = useSceneMode();
  const mobile = mode === 'mobile';

  return (
    <>
      <ambientLight intensity={mobile ? 0.88 : 0.85} />
      <directionalLight
        position={[sceneWidth * 0.5, sceneWidth * (mobile ? 1.2 : 1.4), sceneWidth * 0.45]}
        intensity={mobile ? 1.1 : 1.25}
      />
      <hemisphereLight args={['#fff8ee', SCENE_BACKGROUND, mobile ? 0.62 : 0.58]} />
    </>
  );
}
