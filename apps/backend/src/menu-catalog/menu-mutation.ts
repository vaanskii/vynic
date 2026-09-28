import { BadRequestException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import type { MenuEntityKind } from '@prisma/client';

/**
 * One canonical Menu mutation, as every writer submits it (docs/CANONICAL_MENU_SYNC.md).
 *
 * Identity is the node's stable offline UUID (the `posMenu*Id` column; equal to
 * the row key for Cloud-created nodes). `expectedRevision` is the revision the
 * writer based its change on; 0 means "this node does not exist yet". A patch
 * names only the fields it changes, so a POS price edit never flips
 * Dashboard-owned fields such as `enabled`.
 */
export interface MenuMutation {
  mutationId: string;
  entityType: MenuEntityKind;
  operation: 'UPSERT' | 'DELETE';
  entityId: string;
  expectedRevision: number;
  patch: MenuPatch;
  resolution: 'REAPPLY' | null;
}

export interface MenuPatch {
  nameKa?: string;
  nameEn?: string;
  slug?: string;
  sortOrder?: number;
  sendToKitchen?: boolean;
  enabled?: boolean;
  price?: number;
  size?: number;
  categoryId?: string;
  subcategoryId?: string;
  menuItemId?: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KINDS: Record<string, MenuEntityKind> = {
  CATEGORY: 'CATEGORY',
  SUBCATEGORY: 'SUBCATEGORY',
  ITEM: 'ITEM',
  VARIANT: 'VARIANT',
};
const FIELDS: Record<MenuEntityKind, readonly (keyof MenuPatch)[]> = {
  CATEGORY: ['nameKa', 'nameEn', 'slug', 'sortOrder', 'sendToKitchen'],
  SUBCATEGORY: ['nameKa', 'nameEn', 'slug', 'sortOrder', 'categoryId'],
  ITEM: [
    'nameKa',
    'nameEn',
    'sortOrder',
    'sendToKitchen',
    'enabled',
    'price',
    'categoryId',
    'subcategoryId',
  ],
  VARIANT: ['size', 'price', 'menuItemId'],
};

function bad(message: string): never {
  throw new BadRequestException({ code: 'INVALID_MUTATION', message });
}

export function uuid(value: unknown, field: string): string {
  if (typeof value !== 'string' || !UUID.test(value))
    bad(`${field} must be a UUID`);
  return value.toLowerCase();
}

function name(value: unknown, field: string) {
  if (typeof value !== 'string' || value.length > 120) bad(`Invalid ${field}`);
  return value.trim();
}

/**
 * Money follows the existing Menu convention (GEL major units as a number,
 * `Float` in PostgreSQL, `double` on the POS) and is refused beyond minor
 * units, so no writer can store a price that rounds differently elsewhere.
 */
export function money(value: unknown, field: string) {
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    value < 0 ||
    value > 1_000_000 ||
    Math.abs(value * 100 - Math.round(value * 100)) > 1e-6
  )
    bad(`Invalid ${field}`);
  return Math.round(value * 100) / 100;
}

function patchOf(kind: MenuEntityKind, raw: unknown): MenuPatch {
  if (raw === undefined || raw === null) return {};
  if (typeof raw !== 'object' || Array.isArray(raw))
    bad('patch must be an object');
  const source = raw as Record<string, unknown>;
  const allowed = FIELDS[kind];
  const patch: MenuPatch = {};
  for (const [key, value] of Object.entries(source)) {
    if (value === undefined) continue;
    if (!allowed.includes(key as keyof MenuPatch))
      bad(`${key} is not a ${kind.toLowerCase()} field`);
    switch (key) {
      case 'nameKa':
      case 'nameEn':
        patch[key] = name(value, key);
        break;
      case 'slug': {
        const slug = name(value, key);
        if (!slug) bad('Invalid slug');
        patch.slug = slug;
        break;
      }
      case 'sortOrder':
        if (
          typeof value !== 'number' ||
          !Number.isInteger(value) ||
          value < 0 ||
          value > 1_000_000
        )
          bad('Invalid sortOrder');
        patch.sortOrder = value;
        break;
      case 'sendToKitchen':
      case 'enabled':
        if (typeof value !== 'boolean') bad(`Invalid ${key}`);
        patch[key] = value;
        break;
      case 'price':
        patch.price = money(value, 'price');
        break;
      case 'size':
        if (
          typeof value !== 'number' ||
          !Number.isFinite(value) ||
          value <= 0 ||
          value > 1000
        )
          bad('Invalid size');
        patch.size = value;
        break;
      case 'categoryId':
      case 'subcategoryId':
      case 'menuItemId':
        patch[key] = uuid(value, key);
        break;
    }
  }
  if (patch.categoryId && patch.subcategoryId && kind === 'ITEM')
    bad('An item has one parent: categoryId or subcategoryId');
  return patch;
}

/** Validates one mutation. Structure only; revisions and tenancy are checked in the transaction. */
export function normalizeMutation(raw: unknown): MenuMutation {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw))
    bad('Mutation object required');
  const body = raw as Record<string, unknown>;
  const kind =
    typeof body.entityType === 'string'
      ? KINDS[body.entityType.toUpperCase()]
      : undefined;
  if (!kind) bad('Unknown entityType');
  if (body.operation !== 'UPSERT' && body.operation !== 'DELETE')
    bad('operation must be UPSERT or DELETE');
  const expected = body.expectedRevision;
  if (
    typeof expected !== 'number' ||
    !Number.isInteger(expected) ||
    expected < 0
  )
    bad('expectedRevision must be a non-negative integer');
  if (body.resolution != null && body.resolution !== 'REAPPLY')
    bad('Unknown resolution');
  const operation = body.operation;
  const patch = operation === 'DELETE' ? {} : patchOf(kind, body.patch);
  if (operation === 'DELETE' && body.patch != null)
    bad('A delete carries no patch');
  return {
    mutationId: uuid(body.mutationId, 'mutationId'),
    entityType: kind,
    operation,
    entityId: uuid(body.entityId, 'entityId'),
    expectedRevision: expected,
    patch,
    resolution: body.resolution === 'REAPPLY' ? 'REAPPLY' : null,
  };
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [
          key,
          canonical((value as Record<string, unknown>)[key]),
        ]),
    );
  return value;
}

/** Content identity of a mutation; the id alone never authorizes a different change. */
export function requestHash(m: MenuMutation): string {
  const content: Omit<MenuMutation, 'mutationId'> & { mutationId?: string } = {
    ...m,
  };
  delete content.mutationId;
  return createHash('sha256')
    .update(JSON.stringify(canonical(content)))
    .digest('hex');
}
