import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import {
  actionsForEntityType,
  deriveAuditLogEntity,
  isAuditLogEntityType,
  type AuditLogEntityType,
} from '../../pos/audit/audit-log-entity';
import type { TenantContext } from '../../tenancy/tenant-context';

export type AuditLogQuery = {
  from?: string;
  to?: string;
  action?: string;
  entityType?: string;
  entityId?: string;
  actor?: string;
  limit?: string;
  cursor?: string;
};

/** One normalized `previous -> new` pair, whatever shape the writer used. */
type AuditLogChange = {
  field: string;
  previousValue: unknown;
  newValue: unknown;
};

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

/**
 * The reader for the venue-wide audit log.
 *
 * `AuditEventLog` has been written to since the first release and, until now,
 * never read: every staff change, price change, expense and business-date
 * change went into it and came back out nowhere. This is the missing half —
 * "who changed this menu price", "who closed the business day", answered from
 * the rows that were already there.
 *
 * A single Order's lifecycle is deliberately not served from here. That lives
 * in its own `AuditReport` with an ordered timeline; this feed is the rest of
 * the restaurant, newest first.
 */
@Injectable()
export class MobileAuditLogService {
  constructor(private readonly prisma: PrismaService) {}

  async getAuditLog(tenant: TenantContext, query: AuditLogQuery = {}) {
    const limit = this.parseLimit(query.limit);
    const where: Record<string, unknown> = {
      // Server-owned tenancy: the Venue comes from the authenticated Staff,
      // never from anything the client sends.
      venueId: tenant.venueId,
    };

    const createdAt = this.dateRange(query.from, query.to);
    if (createdAt) where.createdAt = createdAt;

    const action = query.action?.trim();
    if (action) where.action = action;

    const actor = query.actor?.trim();
    if (actor) where.userId = actor;

    const entityClauses = this.entityWhere(query.entityType, query.entityId);
    const cursorClause = this.cursorWhere(query.cursor);

    const and: unknown[] = [];
    if (entityClauses) and.push(entityClauses);
    if (cursorClause) and.push(cursorClause);
    if (and.length > 0) where.AND = and;

    const rows = await this.prisma.auditEventLog.findMany({
      where: where as never,
      // Newest first for a recent-activity feed, with `id` as the tie-break so
      // two rows written in the same millisecond keep a stable order — which
      // is what makes the cursor exact rather than approximately right.
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });

    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    const last = page[page.length - 1];

    return {
      items: page.map((row) => this.present(row)),
      nextCursor:
        hasMore && last
          ? this.encodeCursor(last.createdAt as Date, last.id as string)
          : null,
    };
  }

  /** The distinct actions and entity types this Venue has actually recorded. */
  async getAuditLogFacets(tenant: TenantContext) {
    const grouped = await this.prisma.auditEventLog.groupBy({
      by: ['action'],
      where: { venueId: tenant.venueId },
      _count: { action: true },
    });
    const actions = grouped
      .map((row) => ({
        action: row.action,
        count: row._count.action,
        entityType: deriveAuditLogEntity(row.action, {}).entityType,
      }))
      .sort((a, b) => a.action.localeCompare(b.action));

    const entityTypes = Array.from(
      new Set(
        actions
          .map((entry) => entry.entityType)
          .filter((value): value is AuditLogEntityType => value !== null),
      ),
    ).sort();

    return { actions, entityTypes };
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  private parseLimit(raw?: string): number {
    if (!raw) return DEFAULT_LIMIT;
    const parsed = Number.parseInt(raw, 10);
    if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_LIMIT;
    return Math.min(parsed, MAX_LIMIT);
  }

  private dateRange(
    from?: string,
    to?: string,
  ): { gte?: Date; lt?: Date } | null {
    const range: { gte?: Date; lt?: Date } = {};
    if (from?.trim()) {
      const start = new Date(from.trim());
      if (Number.isNaN(start.getTime())) {
        throw new BadRequestException('from must be a date');
      }
      range.gte = start;
    }
    if (to?.trim()) {
      const end = new Date(to.trim());
      if (Number.isNaN(end.getTime())) {
        throw new BadRequestException('to must be a date');
      }
      // A bare `YYYY-MM-DD` names a whole day, so the range runs to the end of
      // it. Otherwise "to=2026-09-05" would exclude everything that happened
      // on the 5th.
      range.lt = /^\d{4}-\d{2}-\d{2}$/.test(to.trim())
        ? new Date(end.getTime() + 24 * 60 * 60 * 1000)
        : end;
    }
    return range.gte || range.lt ? range : null;
  }

  /**
   * The entity filter, over rows that name their subject and rows that do not.
   *
   * Historical rows carry no `entityType` — they predate the column, and this
   * repository does not rewrite audit history to make a query simpler. So an
   * entity filter also matches the actions that *mean* that entity, and an id
   * filter reaches into those rows' own details for the key the action stores
   * its subject under.
   */
  private entityWhere(
    entityTypeRaw?: string,
    entityIdRaw?: string,
  ): Record<string, unknown> | null {
    const entityId = entityIdRaw?.trim() || null;
    const typeText = entityTypeRaw?.trim();

    if (!typeText) {
      if (!entityId) return null;
      // An id with no type can only be matched against the stored column;
      // there is no action set to translate it through.
      return { entityId };
    }
    if (!isAuditLogEntityType(typeText)) {
      throw new BadRequestException(`unknown entityType: ${typeText}`);
    }
    const entityType = typeText.toUpperCase() as AuditLogEntityType;
    const legacyActions = actionsForEntityType(entityType);

    if (!entityId) {
      return {
        OR: [
          { entityType },
          { entityType: null, action: { in: legacyActions } },
        ],
      };
    }

    return {
      OR: [
        { entityType, entityId },
        ...this.legacyIdClauses(entityType, legacyActions, entityId),
      ],
    };
  }

  /**
   * Matching one subject inside rows written before `entityId` existed.
   *
   * The identity is in the row's JSON details under the key that action uses.
   * Numbers are stored as numbers there (an `orderId` is an int), so a numeric
   * id is matched both ways rather than silently missing every row.
   */
  private legacyIdClauses(
    entityType: AuditLogEntityType,
    legacyActions: string[],
    entityId: string,
  ): Record<string, unknown>[] {
    const keys = new Set<string>();
    for (const action of legacyActions) {
      for (const key of deriveAuditLogEntityKeys(action)) keys.add(key);
    }
    const values: unknown[] = [entityId];
    const asNumber = Number(entityId);
    if (entityId !== '' && Number.isFinite(asNumber)) values.push(asNumber);

    const clauses: Record<string, unknown>[] = [];
    for (const key of keys) {
      for (const value of values) {
        clauses.push({
          entityType: null,
          action: { in: legacyActions },
          data: { path: [key], equals: value },
        });
      }
    }
    if (clauses.length === 0) {
      // An entity type whose actions carry no identity key at all. Fall back to
      // the type match so the filter narrows rather than returning nothing.
      return [{ entityType: null, action: { in: legacyActions } }];
    }
    return clauses;
  }

  // ── Cursor ────────────────────────────────────────────────────────────────

  private encodeCursor(createdAt: Date, id: string): string {
    return Buffer.from(`${createdAt.toISOString()}|${id}`, 'utf8').toString(
      'base64url',
    );
  }

  /**
   * Everything strictly after the cursor row in `(createdAt desc, id desc)`.
   *
   * Expressed as a keyset rather than an offset so a row written while the
   * reader pages does not shift the window and hide a row.
   */
  private cursorWhere(cursor?: string): Record<string, unknown> | null {
    const raw = cursor?.trim();
    if (!raw) return null;
    let decoded: string;
    try {
      decoded = Buffer.from(raw, 'base64url').toString('utf8');
    } catch {
      throw new BadRequestException('invalid cursor');
    }
    const separator = decoded.lastIndexOf('|');
    if (separator <= 0) throw new BadRequestException('invalid cursor');
    const createdAt = new Date(decoded.slice(0, separator));
    const id = decoded.slice(separator + 1);
    if (Number.isNaN(createdAt.getTime()) || id.length === 0) {
      throw new BadRequestException('invalid cursor');
    }
    return {
      OR: [{ createdAt: { lt: createdAt } }, { createdAt, id: { lt: id } }],
    };
  }

  // ── Presentation ──────────────────────────────────────────────────────────

  private present(row: {
    id: string;
    action: string;
    userId: string;
    entityType: string | null;
    entityId: string | null;
    data: unknown;
    deviceType: string;
    createdAt: Date;
  }) {
    const data = this.asObject(row.data);
    const derived = deriveAuditLogEntity(row.action, data);
    return {
      id: row.id,
      action: row.action,
      // Stored identity when the writer supplied it, derived otherwise, so a
      // row from before the columns existed still displays as what it is.
      entityType: row.entityType ?? derived.entityType,
      entityId: row.entityId ?? derived.entityId,
      entityLabel: this.entityLabel(data),
      actorId: row.userId,
      actorName: this.text(data.actorName) ?? row.userId,
      source: this.text(data.source),
      businessDate: this.text(data.businessDate),
      deviceType: row.deviceType,
      createdAt: row.createdAt.toISOString(),
      changes: this.changes(data),
      // The whole record stays inspectable; the fields above are what a
      // timeline renders without dumping JSON at a manager.
      data,
    };
  }

  /** A human name for the subject, when the row carries one. */
  private entityLabel(data: Record<string, unknown>): string | null {
    for (const key of [
      'staffName',
      'itemName',
      'categoryName',
      'name',
      'customerName',
      'description',
    ]) {
      const value = this.text(data[key]);
      if (value) return value;
    }
    return null;
  }

  /**
   * The fields that moved, from whichever shape the writer used: an explicit
   * `changes` list, or the flat `field`/`previousValue`/`newValue` triple the
   * older money and reservation writers use.
   */
  private changes(data: Record<string, unknown>): AuditLogChange[] {
    const listed = data.changes;
    if (Array.isArray(listed)) {
      return listed
        .filter(
          (entry): entry is Record<string, unknown> =>
            entry !== null && typeof entry === 'object',
        )
        .map((entry) => ({
          field: String(entry.field ?? ''),
          previousValue: entry.previousValue ?? null,
          newValue: entry.newValue ?? null,
        }))
        .filter((change) => change.field.length > 0);
    }
    const field = this.text(data.field);
    if (field && ('previousValue' in data || 'newValue' in data)) {
      return [
        {
          field,
          previousValue: data.previousValue ?? null,
          newValue: data.newValue ?? null,
        },
      ];
    }
    if (
      this.text(data.previousStatus) !== null ||
      this.text(data.newStatus) !== null
    ) {
      return [
        {
          field: 'status',
          previousValue: data.previousStatus ?? null,
          newValue: data.newStatus ?? null,
        },
      ];
    }
    return [];
  }

  private asObject(raw: unknown): Record<string, unknown> {
    if (raw !== null && typeof raw === 'object' && !Array.isArray(raw)) {
      return raw as Record<string, unknown>;
    }
    return {};
  }

  private text(raw: unknown): string | null {
    if (typeof raw !== 'string') return null;
    const trimmed = raw.trim();
    return trimmed.length === 0 ? null : trimmed;
  }
}

/**
 * The `data` keys one action stores its subject's identity under.
 *
 * Derived from the same registry the entity mapping uses, by asking it what a
 * row carrying only that key would resolve to. Keeping the key list in one
 * place is the point: a rule added there is found here without being repeated.
 */
function deriveAuditLogEntityKeys(action: string): string[] {
  const candidates = [
    'reservationId',
    'orderId',
    'saleId',
    'closureId',
    'newDate',
    'field',
    'staffName',
    'itemId',
    'itemName',
    'categoryName',
    'packageId',
    'expenseId',
    'businessDateClosed',
    'businessDate',
    'backupCreatedAt',
  ];
  const keys: string[] = [];
  for (const key of candidates) {
    const probe = deriveAuditLogEntity(action, { [key]: '__probe__' });
    if (probe.entityId === '__probe__') keys.push(key);
  }
  return keys;
}
