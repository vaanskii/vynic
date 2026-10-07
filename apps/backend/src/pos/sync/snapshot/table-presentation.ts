import { BadRequestException } from '@nestjs/common';
import { isCanonicalTableId } from '../../../shared/contracts/table-identity';
import type { TableLayoutSync, TableSync } from '../sync-payload';

const fields = [
  'tableKind',
  'tableLabel',
  'floorLabel',
  'tableSortOrder',
  'floorSortOrder',
] as const;

export function tablePresentation(table: TableSync) {
  return Object.fromEntries(
    fields
      .filter((key) => table[key] !== undefined)
      .map((key) => [key, table[key]]),
  );
}

/** Validate the entire modern projection before its first write. */
export function validateTablePresentation(
  tables: TableSync[] | undefined,
  layout?: TableLayoutSync,
): void {
  const invalid = () => {
    throw new BadRequestException('Invalid POS table layout projection');
  };
  if (tables !== undefined && !Array.isArray(tables)) invalid();
  const aliases = new Set<string>();
  const ids = new Set<string>();
  const physical = new Set<string>();
  const floors = new Map<string, string>();
  for (const table of tables ?? []) {
    if (!table || typeof table !== 'object') invalid();
    const hasPresentation = fields.some((key) => table[key] !== undefined);
    if (!hasPresentation && layout === undefined) continue;
    if (
      typeof table.tableNumber !== 'string' ||
      !table.tableNumber.trim() ||
      typeof table.floor !== 'string' ||
      !table.floor.trim()
    )
      invalid();
    const alias = JSON.stringify([table.floor, table.tableNumber]);
    if (aliases.has(alias)) invalid();
    aliases.add(alias);
    if (table.tableId !== undefined) {
      if (!isCanonicalTableId(table.tableId) || ids.has(table.tableId))
        invalid();
      ids.add(table.tableId);
    }
    if (table.tableKind !== 'PHYSICAL' && table.tableKind !== 'VIRTUAL')
      invalid();
    if (table.tableKind === 'VIRTUAL') {
      if (fields.slice(1).some((key) => table[key] !== undefined)) invalid();
      continue;
    }
    if (!table.tableId) invalid();
    for (const key of ['tableLabel', 'floorLabel'] as const) {
      if (
        typeof table[key] !== 'string' ||
        !table[key]!.trim() ||
        table[key]!.length > 512
      )
        invalid();
    }
    for (const key of ['tableSortOrder', 'floorSortOrder'] as const) {
      if (!Number.isInteger(table[key]) || Math.abs(table[key]!) > 2147483647)
        invalid();
    }
    physical.add(table.tableId!);
    const floor = JSON.stringify([table.floorLabel, table.floorSortOrder]);
    if (floors.has(table.floor) && floors.get(table.floor) !== floor) invalid();
    floors.set(table.floor, floor);
  }
  if (layout === undefined) return;
  if (
    !layout ||
    layout.version !== 1 ||
    !Array.isArray(layout.physicalTableIds) ||
    tables === undefined
  )
    invalid();
  const membership = new Set(layout.physicalTableIds);
  if (
    membership.size !== layout.physicalTableIds.length ||
    membership.size !== physical.size ||
    [...membership].some((id) => !isCanonicalTableId(id) || !physical.has(id))
  )
    invalid();
}
