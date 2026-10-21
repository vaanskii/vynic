import { BadRequestException } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { MobileDevicesService } from './mobile-devices.service';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import type { TenantContext } from '../../tenancy/tenant-context';

const url = process.env.TENANT_INTEGRATION_DATABASE_URL;
(url ? describe : describe.skip)(
  'Manager notification paging / disposable PostgreSQL',
  () => {
    let db: PrismaService;
    let service: MobileDevicesService;
    let venueA: TenantContext;
    let venueB: TenantContext;
    const username = 'synthetic-same-manager';
    const at = new Date('2026-10-07T09:00:00.000Z');

    beforeAll(async () => {
      if (!url || !isFreshDisposableDatabase(url)) {
        throw new Error('Use an owned fresh disposable database');
      }
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      service = new MobileDevicesService(db);
      const organization = await db.organization.create({
        data: { name: 'Synthetic notification paging' },
      });
      for (const name of ['A', 'B']) {
        const venue = await db.venue.create({
          data: {
            organizationId: organization.id,
            name: `Synthetic notification ${name}`,
            timezone: 'Asia/Tbilisi',
            currency: 'GEL',
          },
        });
        const tenant = {
          venueId: venue.id,
          organizationId: organization.id,
        };
        if (name === 'A') venueA = tenant;
        else venueB = tenant;
      }
    });

    afterAll(async () => {
      await db?.$disconnect();
    });

    beforeEach(async () => {
      await db.managerNotification.deleteMany({
        where: { venueId: { in: [venueA.venueId, venueB.venueId] } },
      });
    });

    const notification = (
      id: string,
      tenant: TenantContext,
      createdAt = at,
      staffUsername = username,
    ) =>
      db.managerNotification.create({
        data: {
          id,
          venueId: tenant.venueId,
          wsType: 'synthetic_notification',
          title: 'Synthetic',
          body: id,
          envelope: {},
          createdAt,
          deliveries: { create: { staffUsername, channel: 'synthetic' } },
        },
      });

    it('drains 205 equal-timestamp deliveries exactly once and excludes other Venue/staff rows', async () => {
      const ids = Array.from(
        { length: 205 },
        (_, index) => `synthetic-${index.toString().padStart(3, '0')}`,
      );
      // Insert in reverse order so database insertion order cannot accidentally
      // substitute for the explicit timestamp/id ordering.
      for (const id of [...ids].reverse()) await notification(id, venueA);
      await notification('foreign-venue', venueB);
      await notification('foreign-staff', venueA, at, 'different-manager');

      const pages = [] as Awaited<
        ReturnType<MobileDevicesService['getNotificationsPage']>
      >[];
      let cursor: string | undefined;
      do {
        const page = await service.getNotificationsPage(
          venueA,
          username,
          at.toISOString(),
          cursor,
        );
        pages.push(page);
        cursor = page.nextCursor ?? undefined;
      } while (cursor);

      expect(pages.map((page) => page.items.length)).toEqual([100, 100, 5]);
      expect(new Set(pages.map((page) => page.watermark)).size).toBe(1);
      expect(
        pages.flatMap((page) => page.items.map((item) => item.id)),
      ).toEqual(ids);
      expect(
        (
          await service.getNotificationsPage(venueB, username, at.toISOString())
        ).items.map((item) => item.id),
      ).toEqual(['foreign-venue']);
    });

    it('holds its original watermark when a notification arrives during the drain', async () => {
      for (let index = 0; index < 101; index++) {
        await notification(`old-${index.toString().padStart(3, '0')}`, venueA);
      }
      const first = await service.getNotificationsPage(
        venueA,
        username,
        at.toISOString(),
      );
      expect(first.nextCursor).not.toBeNull();
      const arrival = new Date(
        Math.max(Date.now(), Date.parse(first.watermark) + 1),
      );
      await notification('arrived-during-drain', venueA, arrival);
      const second = await service.getNotificationsPage(
        venueA,
        username,
        // Cursor owns both window boundaries; this later supplied date cannot
        // silently change the window halfway through paging.
        arrival.toISOString(),
        first.nextCursor!,
      );
      expect(second.watermark).toBe(first.watermark);
      expect(second.items.map((item) => item.id)).toEqual(['old-100']);
      expect(second.nextCursor).toBeNull();
      const nextCatchUp = await service.getNotificationsPage(
        venueA,
        username,
        first.watermark,
      );
      expect(nextCatchUp.items.map((item) => item.id)).toEqual([
        'arrived-during-drain',
      ]);
    });

    it('initial catch-up defaults to the server 24-hour window', async () => {
      await notification(
        'too-old',
        venueA,
        new Date(Date.now() - 26 * 60 * 60 * 1000),
      );
      await notification(
        'recent',
        venueA,
        new Date(Date.now() - 60 * 60 * 1000),
      );
      await notification(
        'future',
        venueA,
        new Date(Date.now() + 60 * 60 * 1000),
      );
      const page = await service.getNotificationsPage(venueA, username);
      expect(page.items.map((item) => item.id)).toEqual(['recent']);
      expect(Number.isFinite(Date.parse(page.watermark))).toBe(true);
    });

    it('rejects malformed cursors and timestamps before reading data', async () => {
      const encode = (value: unknown) =>
        Buffer.from(JSON.stringify(value)).toString('base64url');
      for (const cursor of [
        'invalid',
        'a'.repeat(2001),
        encode(null),
        encode({
          since: at.toISOString(),
          through: at.toISOString(),
          at: at.toISOString(),
        }),
        encode({
          since: 'invalid',
          through: at.toISOString(),
          at: at.toISOString(),
          id: 'id',
        }),
        encode({
          since: at.toISOString(),
          through: at.toISOString(),
          at: at.toISOString(),
          id: 'a'.repeat(101),
        }),
        encode({
          since: '2026-10-08T00:00:00.000Z',
          through: at.toISOString(),
          at: at.toISOString(),
          id: 'id',
        }),
        encode({
          since: at.toISOString(),
          through: at.toISOString(),
          at: '2026-10-08T00:00:00.000Z',
          id: 'id',
        }),
      ]) {
        await expect(
          service.getNotificationsPage(venueA, username, undefined, cursor),
        ).rejects.toBeInstanceOf(BadRequestException);
      }
      await expect(
        service.getNotificationsPage(venueA, username, 'invalid'),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  },
);
