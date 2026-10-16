import { PrismaService } from '../../../prisma.service';
import { ReservationSyncService } from './reservation-sync.service';
import { isFreshDisposableDatabase } from '../../../../test/disposable-database';
import type { ReservationSync } from '../sync-payload';

const url = process.env.POS_CHECKOUT_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'POS reservation advance mirror / PostgreSQL',
  () => {
    let db: PrismaService;
    let service: ReservationSyncService;
    let venueId: string;
    let otherVenue: string;
    beforeAll(async () => {
      if (
        !url ||
        !isFreshDisposableDatabase(url) ||
        !new URL(url).pathname.includes('pos_checkout')
      )
        throw Error('Use an owned disposable_pos_checkout database');
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const org = await db.organization.create({
        data: { name: 'Synthetic checkout proof' },
      });
      venueId = (
        await db.venue.create({
          data: {
            organizationId: org.id,
            name: 'Synthetic A',
            currency: 'GEL',
            timezone: 'Asia/Tbilisi',
          },
        })
      ).id;
      otherVenue = (
        await db.venue.create({
          data: {
            organizationId: org.id,
            name: 'Synthetic B',
            currency: 'GEL',
            timezone: 'Asia/Tbilisi',
          },
        })
      ).id;
      service = new ReservationSyncService(db);
    });
    afterAll(async () => {
      await db?.$disconnect();
    });
    const booking = (id: string, amount = 6): ReservationSync => ({
      id,
      customerName: 'Synthetic guest',
      customerPhone: '',
      reservationDate: '2026-10-17T00:00:00.000Z',
      reservationTime: '18:00',
      status: 'hold',
      advanceAmount: amount,
      advanceCollectedOn: '2026-10-15',
      advanceReceiptId: `reservation:${id}:advance`,
    });
    const row = (id: string, tenant = venueId) =>
      db.posReservation.findUniqueOrThrow({
        where: {
          venueId_posReservationId: { venueId: tenant, posReservationId: id },
        },
      });
    it('keeps holds distinct and receipt facts through same retry and old omitted fields', async () => {
      const payload = booking('same');
      await service.sync({ venueId }, [payload], true);
      await service.sync({ venueId }, [payload], true);
      const {
        advanceAmount: _a,
        advanceCollectedOn: _d,
        advanceReceiptId: _r,
        ...old
      } = payload;
      await service.sync(
        { venueId },
        [{ ...old, customerName: 'Updated contact' }],
        true,
      );
      expect((await row('same')).advanceAmount.toString()).toBe('6');
      expect(await row('same')).toMatchObject({
        status: 'hold',
        customerName: 'Updated contact',
        advanceCollectedOn: '2026-10-15',
        advanceReceiptId: 'reservation:same:advance',
      });
    });
    it('serializes simultaneous different receipt claims without last-writer replacement', async () => {
      const outcomes = await Promise.allSettled([
        service.sync({ venueId }, [booking('race', 4)], true),
        service.sync({ venueId }, [booking('race', 6)], true),
      ]);
      expect(outcomes.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      expect(outcomes.filter((r) => r.status === 'rejected')).toHaveLength(1);
      expect(['4', '6']).toContain(
        (await row('race')).advanceAmount.toString(),
      );
    });
    it('keeps a recorded booking on invalid best-effort money input and refuses zeroing it', async () => {
      await service.sync({ venueId }, [booking('protected')], true);
      await expect(
        service.sync(
          { venueId },
          [
            {
              ...booking('protected'),
              advanceAmount: 0,
              advanceCollectedOn: null,
              advanceReceiptId: null,
            },
          ],
          true,
        ),
      ).rejects.toThrow('cannot be rewritten');
      const result = await service.sync({ venueId }, [
        { ...booking('protected'), advanceAmount: -1 },
      ]);
      expect(result.complete).toBe(false);
      expect((await row('protected')).advanceAmount.toString()).toBe('6');
    });
    it('scopes matching reservation/receipt names to the server-owned Venue', async () => {
      await service.sync({ venueId }, [booking('shared')], true);
      await service.sync({ venueId: otherVenue }, [booking('shared', 4)], true);
      expect((await row('shared')).advanceAmount.toString()).toBe('6');
      expect((await row('shared', otherVenue)).advanceAmount.toString()).toBe(
        '4',
      );
    });
    it('database itself rejects negative advances', async () => {
      await expect(
        db.$executeRaw`UPDATE "pos"."PosReservation" SET "advanceAmount"=-1 WHERE "venueId"=${venueId}`,
      ).rejects.toThrow();
    });
    it('accepts the existing outer snapshot transaction without nesting another transaction', async () => {
      await db.$transaction(async (tx) => {
        const transactional = new ReservationSyncService(tx as PrismaService);
        await transactional.sync(
          { venueId },
          [booking('outer-transaction')],
          true,
        );
      });
      expect((await row('outer-transaction')).advanceAmount.toString()).toBe(
        '6',
      );
    });
  },
);
