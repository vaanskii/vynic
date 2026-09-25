import { useCallback, Suspense, useState, useMemo, type ReactNode } from 'react';
import { Canvas } from '@react-three/fiber';
import * as THREE from 'three';
import floor1SvgUrl from '../../assets/floor1.svg';
import floor2SvgUrl from '../../assets/floor2.svg';
import { SceneModeProvider } from './context/SceneModeContext';
import { useInteractionMode } from './hooks/useInteractionMode';
import { useSvgFloorPlan } from './hooks/useSvgFloorPlan';
import { useTableStates } from './hooks/useTableStates';
import { RestaurantScene } from './RestaurantScene';
import { SCENE_BACKGROUND } from './constants';
import type { TableStatus } from './types';
import { getTableState } from './utils/tableStateLookup';
import { getViewBox } from './utils/coordinates';
import { computeFloor2GhostOffset } from './utils/floorAlignment';
import { getOverviewCamera, offsetCameraXZ } from './utils/cameraView';
import { getAdaptiveDpr, shouldUseAntialias } from './utils/performance';
import type { Map3DLabels, MapLanguage } from './mapLabels';
import { MAP_LABELS, tableDisplayNumber } from './mapLabels';
import { MobileSelectionBar } from './MobileSelectionBar';

export interface Restaurant3DMapProps {
  floorId?: 'floor1' | 'floor2';
  date?: string;
  language?: MapLanguage;
  labels?: Map3DLabels;
  onTableSelectionChange?: (tableIds: string[]) => void;
  onReserve?: (tableIds: string[]) => void;
  reserveButtonLabel?: string;
  selectedTableIds?: string[];
  pollInterval?: number;
  className?: string;
  topBar?: ReactNode;
}

function todayIso(): string {
  return new Date().toISOString().split('T')[0];
}

const STATUS_DOT: Record<TableStatus, string> = {
  available: '#4ade80',
  reserved: '#f87171',
  pending: '#facc15',
  unknown: '#c0ad7b',
};

function MapPanel({
  children,
  className = '',
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`border border-white/10 bg-[#0a0a0a] ${className}`}>
      {children}
    </div>
  );
}

function sortTableIds(ids: string[]): string[] {
  return [...ids].sort(
    (a, b) => parseInt(a.replace(/\D/g, ''), 10) - parseInt(b.replace(/\D/g, ''), 10),
  );
}

export function Restaurant3DMap({
  floorId,
  date = todayIso(),
  language = 'en',
  labels: labelsOverride,
  onTableSelectionChange,
  onReserve,
  reserveButtonLabel,
  selectedTableIds: controlledSelected,
  pollInterval,
  className = '',
  topBar,
}: Restaurant3DMapProps) {
  const labels = labelsOverride ?? MAP_LABELS[language];
  const continueLabel = reserveButtonLabel ?? labels.continueBooking;
  const pageBackground = SCENE_BACKGROUND;

  const interactionMode = useInteractionMode();
  const mobile = interactionMode === 'mobile';

  const floorDebug = useMemo(() => {
    if (typeof window === 'undefined') return false;
    return new URLSearchParams(window.location.search).get('floorDebug') === '1';
  }, []);

  const { floorPlan: floor1Plan, loading: floor1Loading, error: floor1Error } = useSvgFloorPlan(
    floor1SvgUrl,
    'floor1',
  );
  const { floorPlan: floor2Plan, loading: floor2Loading, error: floor2Error } = useSvgFloorPlan(
    floor2SvgUrl,
    'floor2',
  );
  const activeFloor = floorId ?? 'floor1';
  const { tableStates, loading: statesLoading, error: statesError } = useTableStates(date, pollInterval);

  const [internalSelected, setInternalSelected] = useState<string[]>([]);
  const [unavailableToast, setUnavailableToast] = useState<string | null>(null);

  const isControlled = controlledSelected !== undefined;
  const selectedTableIds = isControlled ? controlledSelected : internalSelected;
  const selectedSet = useMemo(() => new Set(selectedTableIds), [selectedTableIds]);

  const applySelection = useCallback(
    (nextIds: string[]) => {
      const sorted = sortTableIds(nextIds);
      if (!isControlled) {
        setInternalSelected(sorted);
      }
      onTableSelectionChange?.(sorted);
    },
    [isControlled, onTableSelectionChange],
  );

  const handleTableClick = useCallback(
    (tableId: string) => {
      const state = tableStates.get(tableId);

      if (state?.status !== 'available') {
        setUnavailableToast(tableId);
        window.setTimeout(() => setUnavailableToast((cur) => (cur === tableId ? null : cur)), 2200);
        return;
      }

      if (selectedSet.has(tableId)) {
        applySelection(selectedTableIds.filter((id) => id !== tableId));
      } else {
        applySelection(sortTableIds([...selectedTableIds, tableId]));
      }
    },
    [applySelection, selectedSet, selectedTableIds, tableStates],
  );

  const handleClearSelection = useCallback(() => {
    applySelection([]);
  }, [applySelection]);

  const handleContinue = useCallback(() => {
    if (selectedTableIds.length === 0) return;
    if (onReserve) {
      onReserve(selectedTableIds);
      return;
    }
    onTableSelectionChange?.(selectedTableIds);
  }, [onReserve, onTableSelectionChange, selectedTableIds]);

  const sceneWidth = getViewBox().width * 0.01;
  const floor2Offset = useMemo(() => {
    const floor1Anchor = floor1Plan?.alignAnchor;
    const floor2Anchor = floor2Plan?.alignAnchor;
    if (!floor1Anchor || !floor2Anchor) return [0, 0, 0] as [number, number, number];
    return computeFloor2GhostOffset(floor1Anchor, floor2Anchor);
  }, [floor1Plan?.alignAnchor, floor2Plan?.alignAnchor]);

  const defaultCamera = useMemo(() => {
    if (!floor1Plan || !floor2Plan) return null;
    if (activeFloor === 'floor2') {
      return offsetCameraXZ(getOverviewCamera(floor2Plan, sceneWidth, mobile), floor2Offset);
    }
    return getOverviewCamera(floor1Plan, sceneWidth, mobile);
  }, [floor1Plan, floor2Plan, activeFloor, sceneWidth, mobile, floor2Offset]);

  const svgLoading = floor1Loading || floor2Loading;
  const svgError = floor1Error ?? floor2Error;
  const plansReady = Boolean(!svgLoading && floor1Plan && floor2Plan && defaultCamera);

  if (svgError) {
    return (
      <div
        className="flex h-full min-h-[480px] items-center justify-center text-red-300"
        style={{ backgroundColor: pageBackground }}
      >
        {svgError ?? labels.connectionError}
      </div>
    );
  }

  const selectedStates = selectedTableIds.map((id) => getTableState(tableStates, id));
  const totalSeats = selectedStates.reduce((sum, state) => sum + (state?.capacity ?? 0), 0);
  const canReserve =
    selectedTableIds.length > 0 &&
    selectedStates.every((state) => state?.status === 'available');

  const statusLegend: { status: TableStatus; label: string }[] = [
    { status: 'available', label: labels.statusAvailable },
    { status: 'reserved', label: labels.statusReserved },
    { status: 'pending', label: labels.statusPending },
  ];

  const showSelectionBar = selectedTableIds.length > 0;

  return (
    <div
      className={`flex h-full min-h-0 flex-col overflow-hidden ${className}`}
      style={{ backgroundColor: pageBackground }}
    >
      {/* 3D view — flex-1; all map clicks happen here only */}
      <div className="relative min-h-0 flex-1" style={{ backgroundColor: pageBackground }}>
        {plansReady && defaultCamera && floor1Plan && floor2Plan && (
        <Canvas
          className="!absolute inset-0 touch-none"
          frameloop="demand"
          shadows={false}
          camera={{
            position: defaultCamera.position,
            fov: defaultCamera.fov,
            near: 0.1,
            far: 100,
          }}
          gl={{ antialias: shouldUseAntialias(), alpha: false, powerPreference: 'high-performance' }}
          dpr={getAdaptiveDpr()}
          onCreated={({ gl, scene }) => {
            gl.setClearColor(pageBackground);
            scene.background = new THREE.Color(pageBackground);
          }}
        >
          <SceneModeProvider mode={interactionMode}>
            <Suspense fallback={null}>
              <RestaurantScene
                floor1Plan={floor1Plan}
                floor2Plan={floor2Plan}
                activeFloor={activeFloor}
                tableStates={tableStates}
                selectedTableIds={selectedTableIds}
                onTableClick={handleTableClick}
                interactionMode={interactionMode}
                floorDebug={floorDebug}
              />
            </Suspense>
          </SceneModeProvider>
        </Canvas>
        )}

        {topBar && (
          <div className="pointer-events-none absolute inset-x-0 top-0 z-20 flex justify-center p-3 pt-[max(0.5rem,env(safe-area-inset-top))] sm:p-4 [&>*]:pointer-events-auto">
            {topBar}
          </div>
        )}

        {(statesError || statesLoading) && !showSelectionBar && (
          <div
            className={`pointer-events-none absolute inset-x-0 z-10 flex justify-center px-3 ${
              topBar ? 'top-16' : 'top-3'
            }`}
          >
            <MapPanel className="px-3 py-2 text-center">
              {statesLoading && !statesError && (
                <p className="text-[10px] uppercase tracking-[0.15em] text-white/50">{labels.loadingAvailability}</p>
              )}
              {statesError && <p className="text-xs text-red-400">{labels.connectionError}</p>}
            </MapPanel>
          </div>
        )}

        {unavailableToast && (
          <div className="pointer-events-none absolute inset-x-0 top-24 z-10 flex justify-center px-4">
            <MapPanel className="px-4 py-2.5 text-center">
              <p className="text-xs font-light text-white/80">
                {tableDisplayNumber(unavailableToast)} —{' '}
                {(() => {
                  const s = tableStates.get(unavailableToast)?.status;
                  if (s === 'pending') return labels.statusPending;
                  if (s === 'reserved') return labels.statusReserved;
                  return labels.unavailable;
                })()}
              </p>
            </MapPanel>
          </div>
        )}

        {!showSelectionBar && (
          <div
            className={`pointer-events-none absolute inset-x-0 z-10 flex justify-center px-3 sm:justify-end sm:px-4 ${
              mobile ? 'bottom-3' : 'bottom-3'
            }`}
          >
            <MapPanel className="flex w-full max-w-md items-center justify-center gap-4 px-4 py-2.5 sm:max-w-none sm:gap-6 sm:px-5">
              {statusLegend.map(({ status, label }) => (
                <div key={status} className="flex items-center gap-2">
                  <span
                    className="inline-block h-2 w-2 shrink-0 rounded-full sm:h-2.5 sm:w-2.5"
                    style={{ background: STATUS_DOT[status] }}
                  />
                  <span className="text-[10px] uppercase tracking-[0.15em] text-white/60 sm:text-[11px] sm:tracking-[0.2em]">
                    {label}
                  </span>
                </div>
              ))}
            </MapPanel>
          </div>
        )}

        {mobile && selectedTableIds.length === 0 && (
          <div className="pointer-events-none absolute inset-x-0 bottom-14 z-10 flex justify-center px-4">
            <p className="border border-white/10 bg-[#0a0a0a] px-3 py-1.5 text-[10px] uppercase tracking-[0.15em] text-white/45">
              {labels.mobileTapHint}
            </p>
          </div>
        )}

        {showSelectionBar && (
          <MobileSelectionBar
            labels={labels}
            selectedCount={selectedTableIds.length}
            totalSeats={totalSeats}
            compact={mobile}
            canContinue={canReserve}
            continueLabel={continueLabel}
            onClear={handleClearSelection}
            onContinue={handleContinue}
          />
        )}
      </div>
    </div>
  );
}

export default Restaurant3DMap;
