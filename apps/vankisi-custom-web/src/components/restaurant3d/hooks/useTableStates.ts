import { useCallback, useEffect, useState } from 'react';
import { tableService } from '../../../services/api';
import type { TableAvailability, TableState, TableStatus } from '../types';

const DEFAULT_POLL_MS = 15_000;

function toStatus(entry: TableAvailability, pendingTables: Set<string>): TableStatus {
  if (pendingTables.has(entry.tableNumber)) return 'pending';
  return entry.isAvailable ? 'available' : 'reserved';
}

export function useTableStates(date: string, pollInterval = DEFAULT_POLL_MS) {
  const [tableStates, setTableStates] = useState<Map<string, TableState>>(new Map());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchStates = useCallback(async () => {
    try {
      const [tables, availability, reservations] = await Promise.all([
        tableService.getAllTables(),
        tableService.getTableAvailability(date),
        tableService.getReservationsForDate(date).catch(() => []),
      ]);

      const pendingTables = new Set<string>();
      for (const reservation of reservations as Array<{ status?: string; tables?: Array<{ table: { tableNumber: string } }> }>) {
        if (reservation.status === 'PENDING') {
          reservation.tables?.forEach((rt) => pendingTables.add(rt.table.tableNumber));
        }
      }

      const availabilityByNumber = new Map(
        (availability as TableAvailability[]).map((row) => [row.tableNumber, row]),
      );

      const next = new Map<string, TableState>();
      for (const table of tables as Array<{ id: string; tableNumber: string; capacity: number }>) {
        const avail = availabilityByNumber.get(table.tableNumber);
        next.set(table.tableNumber, {
          id: table.id,
          tableNumber: table.tableNumber,
          capacity: table.capacity,
          status: avail ? toStatus(avail, pendingTables) : 'unknown',
        });
      }

      setTableStates(next);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load table states');
    } finally {
      setLoading(false);
    }
  }, [date]);

  useEffect(() => {
    fetchStates();
    if (pollInterval <= 0) return undefined;

    const id = window.setInterval(fetchStates, pollInterval);
    return () => window.clearInterval(id);
  }, [fetchStates, pollInterval]);

  return { tableStates, loading, error, refresh: fetchStates };
}
