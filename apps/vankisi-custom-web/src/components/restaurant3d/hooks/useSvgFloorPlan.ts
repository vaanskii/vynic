import { useEffect, useState } from 'react';
import type { FloorId, FloorPlanData } from '../types';
import { parseFloorPlanSvg } from '../utils/svgParser';

interface UseSvgFloorPlanResult {
  floorPlan: FloorPlanData | null;
  loading: boolean;
  error: string | null;
}

/** Bump when parser output shape changes so dev HMR picks up railing fixes */
const PARSE_CACHE_VERSION = 'floor2-railing-v15-entrance-walls';

/** Module-level cache — SVG parse runs once per source URL + floor */
const parseCache = new Map<string, FloorPlanData>();

export function useSvgFloorPlan(svgSource: string, floorId?: FloorId): UseSvgFloorPlanResult {
  const cacheKey = floorId
    ? `${svgSource}::${floorId}::${PARSE_CACHE_VERSION}`
    : `${svgSource}::${PARSE_CACHE_VERSION}`;
  const cached = parseCache.get(cacheKey);

  const [floorPlan, setFloorPlan] = useState<FloorPlanData | null>(cached ?? null);
  const [loading, setLoading] = useState(!cached);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (parseCache.has(cacheKey)) {
      setFloorPlan(parseCache.get(cacheKey)!);
      setLoading(false);
      return;
    }

    let cancelled = false;

    const parse = async () => {
      setLoading(true);
      setError(null);

      try {
        const svgText = svgSource.trim().startsWith('<')
          ? svgSource
          : await (await fetch(svgSource)).text();

        const data = parseFloorPlanSvg(svgText, floorId);
        parseCache.set(cacheKey, data);

        if (!cancelled) {
          setFloorPlan(data);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Failed to parse floor plan SVG');
          setFloorPlan(null);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    parse();
    return () => {
      cancelled = true;
    };
  }, [svgSource, cacheKey, floorId]);

  return { floorPlan, loading, error };
}
