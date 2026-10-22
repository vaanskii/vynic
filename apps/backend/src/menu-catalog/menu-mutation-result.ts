import {
  ConflictException,
  InternalServerErrorException,
} from '@nestjs/common';
import type { MenuCatalogMutation } from '@prisma/client';
import type { MutationAccepted } from './menu-catalog.service';

/** Replay only server-generated durable results; never reconstruct from live rows. */
export function replayAcceptedMutation(
  prior: MenuCatalogMutation,
): MutationAccepted {
  if (prior.acceptedResult === null)
    throw new ConflictException({
      code: 'MUTATION_RESULT_UNAVAILABLE',
      message:
        'This legacy mutation was accepted, but its original response was not recorded. Resync the catalog and review pending edits.',
      mutationId: prior.mutationId,
      resyncRequired: true,
    });

  const result = prior.acceptedResult as unknown as MutationAccepted;
  if (
    !result ||
    result.status !== 'ACCEPTED' ||
    result.duplicate !== false ||
    result.mutationId !== prior.mutationId ||
    result.entityType !== prior.entityType ||
    result.entityId !== prior.entityId ||
    result.operation !== prior.operation ||
    result.revision !== prior.resultRevision ||
    result.sequence !== prior.seq ||
    result.deleted !== (prior.operation === 'DELETE') ||
    (result.deleted
      ? result.entity !== null
      : !result.entity ||
        result.entity.id !== prior.entityId ||
        result.entity.revision !== prior.resultRevision)
  )
    throw new InternalServerErrorException({
      code: 'MUTATION_RESULT_INVALID',
      message:
        'The stored mutation response is inconsistent; recovery is required',
    });

  // Existing wire metadata describes this delivery. All business fields replay
  // the original response; JSONB key order is not part of the wire contract.
  return { ...result, duplicate: true };
}
