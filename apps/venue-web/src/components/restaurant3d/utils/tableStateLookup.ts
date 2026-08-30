import type { TableState } from '../types';

/** Resolve table state by SVG id (table1) or alternate keys from the API map */
export function getTableState(
  tableStates: Map<string, TableState>,
  tableId: string,
): TableState | undefined {
  const direct = tableStates.get(tableId);
  if (direct) return direct;

  const num = tableId.replace(/\D/g, '');
  if (num) {
    const byNum = tableStates.get(num);
    if (byNum) return byNum;
    const byPrefixed = tableStates.get(`table${num}`);
    if (byPrefixed) return byPrefixed;
  }

  for (const state of tableStates.values()) {
    if (state.tableNumber === tableId) return state;
  }

  return undefined;
}
