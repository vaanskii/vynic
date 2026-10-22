import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import {
  mkdir,
  readFile,
  readdir,
  realpath,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { join } from 'node:path';
import { requireLocalDocker } from './local-docker-guard';
import {
  assertMatrixComplete,
  delegate,
  preservedModels,
  venueFilter,
  venueModels,
} from './deletion-matrix';
import { referencedMedia } from '../website/core/website-media';

export type CleanupScope =
  | { kind: 'all' }
  | {
      kind: 'venue' | 'organization';
      id: string;
      confirmation: string;
      actorId: string;
    };
const root = '/var/lib/vynic/media';
const journalDir = join(root, '.local-customer-cleanup');
const keyPattern =
  /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.webp$/;
async function mediaRoot() {
  if (process.env.WEBSITE_MEDIA_DIR !== root || (await realpath(root)) !== root)
    throw new Error('Local cleanup requires the Docker website-media mount');
}
async function verifyDatabase(tx: Prisma.TransactionClient) {
  const rows = await tx.$queryRaw<
    { name: string; user: string }[]
  >`SELECT current_database() AS name, current_user AS "user"`;
  if (rows[0]?.name !== 'vynic_local_prod' || rows[0]?.user !== 'vynic')
    throw new Error('Connected database is not the isolated Docker database');
}

/** Locks keep counts, account relationships, and media ownership stable during local maintenance. */
async function lockTables(tx: Prisma.TransactionClient) {
  await tx.$executeRawUnsafe("SET LOCAL lock_timeout = '5s'");
  const tables = Prisma.dmmf.datamodel.models
    .map((m) => {
      const schema = (m as typeof m & { schema: string }).schema;
      if (
        !['pos', 'website'].includes(schema) ||
        !/^\w+$/.test(m.dbName || m.name)
      )
        throw new Error('Unexpected schema identifier');
      return `"${schema}"."${m.dbName || m.name}"`;
    })
    .sort();
  // Identifiers come exclusively from the compiled Prisma schema, not input.
  await tx.$executeRawUnsafe(
    `LOCK TABLE ${tables.join(', ')} IN SHARE ROW EXCLUSIVE MODE`,
  );
}

export async function cleanupCustomers(
  db: PrismaClient,
  scope: CleanupScope,
  dryRun = false,
) {
  requireLocalDocker();
  assertMatrixComplete();
  await mediaRoot();
  const result = await db.$transaction(
    async (tx) => {
      await verifyDatabase(tx);
      await lockTables(tx);
      if (scope.kind !== 'all') {
        const record =
          scope.kind === 'venue'
            ? await tx.venue.findUnique({ where: { id: scope.id } })
            : await tx.organization.findUnique({ where: { id: scope.id } });
        if (!record)
          throw new NotFoundException('Local test record no longer exists');
        if (scope.confirmation !== `DELETE ${record.name}`)
          throw new BadRequestException(`Type DELETE ${record.name} exactly`);
      }
      const organizations =
        scope.kind === 'all'
          ? await tx.organization.findMany()
          : scope.kind === 'organization'
            ? await tx.organization.findMany({ where: { id: scope.id } })
            : [];
      const organizationIds = organizations.map((x) => x.id);
      const venues = await tx.venue.findMany({
        where:
          scope.kind === 'all'
            ? {}
            : scope.kind === 'venue'
              ? { id: scope.id }
              : { organizationId: scope.id },
      });
      const venueIds = venues.map((x) => x.id);
      if (scope.kind !== 'all') {
        // Older catalog FKs are not composite tenant keys. Refuse inconsistent
        // ownership rather than cascading into another Venue through a parent.
        const outside = { notIn: venueIds };
        const inside = { in: venueIds };
        if (
          (await tx.menuItem.count({
            where: {
              venueId: outside,
              OR: [
                { category: { venueId: inside } },
                { subcategory: { category: { venueId: inside } } },
              ],
            },
          })) ||
          (await tx.menuConsumptionRecipe.count({
            where: {
              venueId: outside,
              OR: [
                { menuItem: { venueId: inside } },
                { variant: { menuItem: { venueId: inside } } },
              ],
            },
          })) ||
          (await tx.menuConsumptionComponent.count({
            where: { venueId: outside, recipe: { venueId: inside } },
          })) ||
          (await tx.menuItemWebsitePresentation.count({
            where: { venueId: outside, menuItem: { venueId: inside } },
          }))
        )
          throw new BadRequestException(
            'Inconsistent cross-Venue catalog ownership; deletion refused',
          );
      }

      const accounts =
        scope.kind === 'venue'
          ? []
          : await tx.customerAccount.findMany({
              where:
                scope.kind === 'all'
                  ? {}
                  : {
                      OR: [
                        { organizationId: scope.id },
                        { memberships: { some: { organizationId: scope.id } } },
                        {
                          acceptedInvitations: {
                            some: { organizationId: scope.id },
                          },
                        },
                      ],
                    },
              include: {
                memberships: true,
                acceptedInvitations: true,
                enrollments: {
                  include: { venue: { select: { organizationId: true } } },
                },
              },
            });
      const accountIds = accounts
        .filter(
          (a) =>
            scope.kind === 'all' ||
            ((!a.organizationId ||
              organizationIds.includes(a.organizationId)) &&
              a.memberships.every((m) =>
                organizationIds.includes(m.organizationId),
              ) &&
              a.acceptedInvitations.every((i) =>
                organizationIds.includes(i.organizationId),
              ) &&
              a.enrollments.every((e) =>
                organizationIds.includes(e.venue.organizationId),
              )),
        )
        .map((a) => a.id);
      const counts: Record<string, number> = {};
      const preserved: Record<string, number> = {};
      for (const model of preservedModels)
        preserved[model] = await delegate(tx, model).count();
      const steps: { model: string; where: object }[] = venueModels.map(
        (model) => ({
          model,
          where: scope.kind === 'all' ? {} : venueFilter(model, venueIds),
        }),
      );
      steps.push(
        {
          model: 'OnboardingRequest',
          where:
            scope.kind === 'all'
              ? {}
              : {
                  OR: [
                    { requestedVenueId: { in: venueIds } },
                    { approvedVenueId: { in: venueIds } },
                    { requestedByAccountId: { in: accountIds } },
                  ],
                },
        },
        {
          model: 'CustomerAuditEvent',
          where:
            scope.kind === 'all'
              ? {}
              : {
                  customerAccountId: { in: accountIds },
                },
        },
        {
          model: 'OwnerInvitation',
          where:
            scope.kind === 'all'
              ? {}
              : { organizationId: { in: organizationIds } },
        },
        {
          model: 'OrganizationMembership',
          where:
            scope.kind === 'all'
              ? {}
              : { organizationId: { in: organizationIds } },
        },
        { model: 'CustomerAccount', where: { id: { in: accountIds } } },
        ...(scope.kind === 'all' ? [{ model: 'WebsiteUser', where: {} }] : []),
        { model: 'Venue', where: { id: { in: venueIds } } },
        { model: 'Organization', where: { id: { in: organizationIds } } },
      );
      for (const step of steps)
        counts[step.model] = await delegate(tx, step.model).count({
          where: step.where,
        });
      preserved.CustomerAccount =
        (await tx.customerAccount.count()) - accountIds.length;
      preserved.WebsiteUser =
        scope.kind === 'all' ? 0 : await tx.websiteUser.count();
      preserved.Organization =
        (await tx.organization.count()) - organizationIds.length;
      preserved.Venue = (await tx.venue.count()) - venueIds.length;
      const media = new Set(
        (
          await tx.websiteMediaAsset.findMany({
            where: { venueId: { in: venueIds } },
          })
        ).map((a) => a.storageKey),
      );
      for (const id of venueIds)
        for (const key of await referencedMedia(tx, id)) media.add(key);
      // Fail before deleting DB rows if any tracked file key is unsafe.
      for (const key of media)
        if (!keyPattern.test(key))
          throw new Error(
            'Unsafe media storage key; resolve it before cleanup',
          );
      const summary = {
        dryRun,
        deleted: counts,
        preserved,
        mediaFiles: [...media].sort(),
        journal: null as string | null,
      };
      if (dryRun) return summary;
      if (media.size) {
        await mkdir(journalDir, { recursive: true, mode: 0o700 });
        if ((await realpath(journalDir)) !== journalDir)
          throw new Error('Unsafe media cleanup journal directory');
        summary.journal = `${randomUUID()}.json`;
        // Write before commit. Recovery checks that every target Venue is gone;
        // a rollback can never cause files belonging to surviving Venues to be removed.
        await writeFile(
          join(journalDir, summary.journal),
          JSON.stringify({ venueIds, keys: summary.mediaFiles }),
          { flag: 'wx', mode: 0o600 },
        );
      }
      await tx.venue.updateMany({
        where: { id: { in: venueIds } },
        data: { activeOperationalDeviceId: null },
      });
      // Legacy provenance does not grant access; clear it on retained shared accounts.
      await tx.customerAccount.updateMany({
        where: { organizationId: { in: organizationIds } },
        data: { organizationId: null },
      });
      await tx.payrollAccrual.deleteMany({
        where: {
          ...(scope.kind === 'all' ? {} : { venueId: { in: venueIds } }),
          dayEntryId: { not: null },
        },
      });
      for (const step of steps)
        await delegate(tx, step.model).deleteMany({ where: step.where });
      if (scope.kind !== 'all')
        await tx.platformAuditEvent.create({
          data: {
            platformUserId: scope.actorId,
            action: 'LOCAL_TEST_DATA_DELETED',
            targetType: scope.kind === 'venue' ? 'Venue' : 'Organization',
            targetId: scope.id,
            metadata: { deleted: counts, mediaFiles: media.size },
          },
        });
      return summary;
    },
    { timeout: 60000, maxWait: 10000 },
  );
  const mediaCleanup =
    !dryRun && result.journal
      ? await cleanupMedia(db, result.journal).catch((error) => ({
          removed: 0,
          retained: 0,
          failures: [error instanceof Error ? error.message : String(error)],
        }))
      : { removed: 0, retained: 0, failures: [] as string[] };
  return { ...result, mediaCleanup };
}

/** Deterministic recovery. Never sweep the media directory or touch unlisted assets. */
export async function cleanupMedia(db: PrismaClient, onlyJournal?: string) {
  requireLocalDocker();
  await mediaRoot();
  await verifyDatabase(db);
  const result = { removed: 0, retained: 0, failures: [] as string[] };
  let journals: string[];
  try {
    journals = await readdir(journalDir);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return result;
    throw error;
  }
  if ((await realpath(journalDir)) !== journalDir)
    throw new Error('Unsafe media journal directory');
  for (const name of journals.filter(
    (n) => !onlyJournal || n === onlyJournal,
  )) {
    if (!/^[a-f0-9-]{36}\.json$/.test(name)) continue;
    try {
      const manifest = JSON.parse(
        await readFile(join(journalDir, name), 'utf8'),
      ) as { venueIds: string[]; keys: string[] };
      if (
        !Array.isArray(manifest.venueIds) ||
        !Array.isArray(manifest.keys) ||
        manifest.keys.some((k) => !keyPattern.test(k))
      )
        throw new Error('Invalid cleanup manifest');
      await db.$transaction(
        async (tx) => {
          await lockTables(tx);
          if (
            await tx.venue.count({ where: { id: { in: manifest.venueIds } } })
          )
            throw new Error(
              'Target Venue still exists (rollback or reseed); files retained',
            );
          const references = new Set<string>();
          for (const venue of await tx.venue.findMany({ select: { id: true } }))
            for (const key of await referencedMedia(tx, venue.id))
              references.add(key);
          for (const key of manifest.keys) {
            if (
              references.has(key) ||
              (await tx.websiteMediaAsset.findUnique({
                where: { storageKey: key },
              }))
            ) {
              result.retained++;
              continue;
            }
            try {
              await unlink(join(root, key));
              result.removed++;
            } catch (error) {
              if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
                throw error;
            }
          }
        },
        { timeout: 60000 },
      );
      await unlink(join(journalDir, name));
    } catch (error) {
      result.failures.push(
        `${name}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
  return result;
}
