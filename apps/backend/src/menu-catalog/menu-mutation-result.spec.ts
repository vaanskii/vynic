import {
  ConflictException,
  InternalServerErrorException,
} from '@nestjs/common';
import type { MenuCatalogMutation, Prisma } from '@prisma/client';
import type { MutationAccepted } from './menu-catalog.service';
import { replayAcceptedMutation } from './menu-mutation-result';
import { normalizeMutation, requestHash } from './menu-mutation';

const mutationId = '30000000-0000-4000-8000-000000000001';
const entityId = '30000000-0000-4000-8000-000000000002';
function record(operation: 'UPSERT' | 'DELETE' = 'UPSERT') {
  const result: MutationAccepted = {
    status: 'ACCEPTED',
    duplicate: false,
    mutationId,
    entityType: 'ITEM',
    entityId,
    operation,
    revision: 2,
    sequence: 7,
    deleted: operation === 'DELETE',
    entity:
      operation === 'DELETE'
        ? null
        : {
            id: entityId,
            revision: 2,
            changeSeq: 7,
            price: 12,
            nameEn: 'Original',
          },
  };
  const prior: MenuCatalogMutation = {
    venueId: 'synthetic-venue',
    mutationId,
    entityType: 'ITEM',
    entityId,
    operation,
    expectedRevision: 1,
    resultRevision: 2,
    seq: 7,
    actorType: 'DEVICE',
    actorId: 'synthetic-device',
    source: 'POS',
    requestHash: 'synthetic-hash',
    changes: {},
    resolution: 'REAPPLY',
    createdAt: new Date('2026-10-01T00:00:00Z'),
    acceptedResult: result as unknown as Prisma.JsonObject,
  };
  return { prior, result };
}

describe('MENU03 immutable accepted result', () => {
  it.each(['UPSERT', 'DELETE'] as const)(
    'replays complete %s outcome without a catalog dependency',
    (operation) => {
      const { prior, result } = record(operation);
      const before = JSON.stringify(prior);
      expect(replayAcceptedMutation(prior)).toEqual({
        ...result,
        duplicate: true,
      });
      expect(JSON.stringify(prior)).toBe(before);
    },
  );

  it('refuses to invent historical responses for legacy rows', () => {
    const { prior } = record();
    prior.acceptedResult = null;
    expect(() => replayAcceptedMutation(prior)).toThrow(ConflictException);
    try {
      replayAcceptedMutation(prior);
    } catch (e) {
      expect((e as ConflictException).getResponse()).toMatchObject({
        code: 'MUTATION_RESULT_UNAVAILABLE',
        mutationId,
        resyncRequired: true,
      });
    }
  });

  it.each(['revision', 'entityId', 'deleted', 'status', 'sequence', 'entity'])(
    'refuses a damaged stored %s instead of reporting success',
    (field) => {
      const { prior, result } = record();
      prior.acceptedResult = {
        ...result,
        [field]: null,
      } as unknown as Prisma.JsonObject;
      expect(() => replayAcceptedMutation(prior)).toThrow(
        InternalServerErrorException,
      );
    },
  );

  it('fingerprints normalized content including resolution and expected revision', () => {
    const body = {
      mutationId,
      entityId,
      entityType: 'ITEM',
      operation: 'UPSERT',
      expectedRevision: 1,
      patch: { nameEn: ' Original ', price: 12 },
    };
    const hash = requestHash(normalizeMutation(body));
    expect(
      requestHash(
        normalizeMutation({
          ...body,
          patch: { price: 12, nameEn: 'Original' },
        }),
      ),
    ).toBe(hash);
    for (const change of [
      { expectedRevision: 2 },
      { resolution: 'REAPPLY' },
      { patch: { price: 13 } },
      { entityId: mutationId },
    ])
      expect(requestHash(normalizeMutation({ ...body, ...change }))).not.toBe(
        hash,
      );
  });
});
