import type { Map3DLabels } from './mapLabels';
import type { TableState, TableStatus } from './types';

const STATUS_COLORS: Record<TableStatus, string> = {
  available: '#4ade80',
  reserved: '#f87171',
  pending: '#facc15',
  unknown: '#c0ad7b',
};

export interface TableSelectionSheetProps {
  tableId: string;
  tableState?: TableState;
  labels: Map3DLabels;
  isSelected: boolean;
  selectedTableIds: string[];
  selectedCount: number;
  totalSeats: number;
  canContinue: boolean;
  continueLabel: string;
  onClose: () => void;
  onToggleSelect: () => void;
  onRemoveTable: (tableId: string) => void;
  onClear: () => void;
  onContinue?: () => void;
  overlay?: boolean;
}

/** Compact floating glass card — never shrinks the 3D canvas */
export function TableSelectionSheet({
  tableId,
  tableState,
  labels,
  isSelected,
  selectedTableIds,
  selectedCount,
  totalSeats,
  canContinue,
  continueLabel,
  onClose,
  onToggleSelect,
  onRemoveTable,
  onClear,
  onContinue,
  overlay = false,
}: TableSelectionSheetProps) {
  const status = tableState?.status ?? 'unknown';
  const statusLabel =
    status === 'available'
      ? labels.statusAvailable
      : status === 'reserved'
        ? labels.statusReserved
        : status === 'pending'
          ? labels.statusPending
          : labels.unavailable;
  const canSelect = status === 'available';
  const seats = tableState?.capacity;

  const panel = (
    <div
      className="pointer-events-auto w-[min(100%,20rem)] rounded-2xl border border-white/25 bg-white/10 p-3 shadow-lg shadow-black/30 backdrop-blur-xl backdrop-saturate-150"
      role="dialog"
      aria-live="polite"
    >
      <div className="flex items-start gap-2">
        <span
          className="mt-1.5 h-2 w-2 shrink-0 rounded-full"
          style={{ background: STATUS_COLORS[status] }}
          aria-hidden
        />
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-white">{labels.tableLabel(tableId)}</p>
          <p className="text-[11px] text-white/55">
            {seats != null ? `${seats} ${labels.seats.toLowerCase()}` : '—'}
            <span className="text-white/30"> · </span>
            {statusLabel}
          </p>
        </div>
        <button
          type="button"
          onClick={onClose}
          aria-label={labels.close}
          className="shrink-0 rounded-lg p-1 text-white/45 transition hover:bg-white/10 hover:text-white/80"
        >
          <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      {selectedCount > 1 && (
        <div className="mt-2 flex flex-wrap gap-1">
          {selectedTableIds.map((id) => (
            <button
              key={id}
              type="button"
              onClick={() => onRemoveTable(id)}
              className={`rounded-full px-2 py-0.5 text-[10px] font-medium transition ${
                id === tableId
                  ? 'bg-[#ae895e]/25 text-[#d4b896]'
                  : 'bg-white/10 text-white/70 hover:bg-white/15'
              }`}
            >
              {labels.tableLabel(id)} ×
            </button>
          ))}
        </div>
      )}

      <div className="mt-2.5 flex gap-1.5">
        <button
          type="button"
          disabled={!canSelect}
          onClick={onToggleSelect}
          className="flex-1 rounded-xl border border-white/20 bg-white/5 py-2 text-xs font-medium text-white/90 transition hover:border-white/35 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {isSelected ? labels.deselectTable : labels.selectTable}
        </button>
        {onContinue && (
          <button
            type="button"
            disabled={!canContinue}
            onClick={onContinue}
            className="flex-[1.2] rounded-xl bg-[#ae895e] py-2 text-xs font-semibold text-[#050505] transition disabled:cursor-not-allowed disabled:opacity-40"
          >
            {canContinue ? continueLabel : labels.unavailable}
          </button>
        )}
      </div>

      {selectedCount > 0 && (
        <button
          type="button"
          onClick={onClear}
          className="mt-2 w-full text-center text-[10px] text-white/35 transition hover:text-white/60"
        >
          {labels.clear}
          {totalSeats > 0 && (
            <span className="text-white/25">
              {' '}
              · {selectedCount} {labels.tablesLabel}, {totalSeats} {labels.seatsTotal}
            </span>
          )}
        </button>
      )}
    </div>
  );

  if (overlay) {
    return (
      <>
        <button
          type="button"
          aria-label={labels.close}
          className="pointer-events-auto fixed inset-0 z-30 bg-black/25 backdrop-blur-[1px]"
          onClick={onClose}
        />
        <div className="pointer-events-none fixed inset-x-0 bottom-0 z-40 flex justify-center px-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          {panel}
        </div>
      </>
    );
  }

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-14 z-20 flex justify-center px-3 sm:justify-end sm:pr-4">
      {panel}
    </div>
  );
}
