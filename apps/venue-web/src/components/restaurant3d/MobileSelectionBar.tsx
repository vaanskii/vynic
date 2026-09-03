import type { Map3DLabels } from './mapLabels';

export interface MobileSelectionBarProps {
  labels: Map3DLabels;
  selectedCount: number;
  totalSeats: number;
  canContinue: boolean;
  continueLabel: string;
  compact?: boolean;
  onClear: () => void;
  onContinue: () => void;
}

/** Compact summary bar — table numbers live on the 3D map */
export function MobileSelectionBar({
  labels,
  selectedCount,
  totalSeats,
  canContinue,
  continueLabel,
  compact = false,
  onClear,
  onContinue,
}: MobileSelectionBarProps) {
  return (
    <div
      className={`pointer-events-auto absolute inset-x-0 bottom-0 z-30 px-3 ${
        compact ? 'pb-[max(0.5rem,env(safe-area-inset-bottom))]' : 'pb-[max(0.65rem,env(safe-area-inset-bottom))]'
      }`}
    >
      <div
        className={`mx-auto flex w-full items-center gap-2 border border-white/10 bg-[#0a0a0a] ${
          compact ? 'max-w-lg px-2.5 py-2' : 'max-w-xl px-3 py-2.5'
        }`}
      >
        <div className="min-w-0 flex-1">
          <p className={`font-light text-white ${compact ? 'text-sm' : 'text-base'}`}>
            {totalSeats > 0
              ? `${totalSeats} ${labels.seatsTotal}`
              : selectedCount > 0
                ? `${selectedCount} ${labels.tablesLabel}`
                : '—'}
          </p>
          {selectedCount > 1 && totalSeats > 0 && (
            <p className={`text-white/45 ${compact ? 'text-[10px]' : 'text-xs'}`}>
              {selectedCount} {labels.tablesLabel}
            </p>
          )}
        </div>

        <button
          type="button"
          onClick={onClear}
          className={`shrink-0 border border-white/10 text-[10px] uppercase tracking-[0.15em] text-white/50 transition hover:border-[#ae895e]/40 hover:text-[#ae895e] ${
            compact ? 'px-2.5 py-1.5' : 'px-3 py-2 text-xs'
          }`}
        >
          {labels.clear}
        </button>

        <button
          type="button"
          disabled={!canContinue}
          onClick={onContinue}
          className={`shrink-0 bg-[#ae895e] font-medium uppercase tracking-[0.15em] text-[#050505] transition hover:bg-white disabled:cursor-not-allowed disabled:opacity-45 ${
            compact ? 'px-3 py-1.5 text-[10px]' : 'px-4 py-2 text-xs'
          }`}
        >
          {continueLabel}
        </button>
      </div>
    </div>
  );
}
