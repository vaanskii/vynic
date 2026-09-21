import { ReservationSyncService } from './reservation-sync.service';
import { PrismaService } from '../../../prisma.service';
import type { ReservationSync } from '../sync-payload';

/**
 * What the Cloud reservation mirror holds after a snapshot.
 *
 * The POS used to send every row of its reservation box, which is roughly one
 * row per order it has ever taken, and every consumer here discarded the
 * bookkeeping ones on read. Now the POS sends bookings. These pin the half of
 * that change which lives on this side: the mirror's reconciliation contract
 * turns a narrowed snapshot into a cleaned mirror, and does it per Venue.
 */

const VENUE_A = { venueId: 'venue-aaaa' };
const VENUE_B = { venueId: 'venue-bbbb' };

interface MirrorRow {
  venueId: string;
  posReservationId: string;
  customerName: string;
  status: string;
  isTakeAway: boolean;
  linkedOrderId: number | null;
  notes: string | null;
  reservationDate: Date;
}

interface MirrorKey {
  venueId_posReservationId: { venueId: string; posReservationId: string };
}

/** A `posReservation` table with its real compound unique key. */
class FakeMirror {
  readonly rows: MirrorRow[] = [];

  private find(where: MirrorKey): MirrorRow | undefined {
    const { venueId, posReservationId } = where.venueId_posReservationId;
    return this.rows.find(
      (row) =>
        row.venueId === venueId && row.posReservationId === posReservationId,
    );
  }

  readonly posReservation = {
    upsert: ({
      where,
      update,
      create,
    }: {
      where: MirrorKey;
      update: Partial<MirrorRow>;
      create: MirrorRow;
    }) => {
      const row = this.find(where);
      if (row) Object.assign(row, update);
      else this.rows.push({ ...create });
      return Promise.resolve(null);
    },
    deleteMany: ({
      where,
    }: {
      where: { venueId: string; posReservationId: { notIn: string[] } };
    }) => {
      const keep = new Set(where.posReservationId.notIn);
      let count = 0;
      for (let i = this.rows.length - 1; i >= 0; i--) {
        const row = this.rows[i];
        if (row.venueId === where.venueId && !keep.has(row.posReservationId)) {
          this.rows.splice(i, 1);
          count++;
        }
      }
      return Promise.resolve({ count });
    },
  };

  idsFor(venueId: string): string[] {
    return this.rows
      .filter((row) => row.venueId === venueId)
      .map((row) => row.posReservationId)
      .sort();
  }

  seed(
    ...rows: Array<
      Partial<MirrorRow> & { posReservationId: string; venueId: string }
    >
  ) {
    for (const row of rows) {
      this.rows.push({
        customerName: 'seeded',
        status: 'confirmed',
        isTakeAway: false,
        linkedOrderId: null,
        notes: null,
        reservationDate: new Date('2026-09-01T00:00:00.000Z'),
        ...row,
      });
    }
  }
}

function makeService() {
  const mirror = new FakeMirror();
  const service = new ReservationSyncService(
    mirror as unknown as PrismaService,
  );
  return { mirror, service };
}

function booking(
  id: string,
  extra: Partial<ReservationSync> = {},
): ReservationSync {
  return {
    id,
    customerName: 'Nino Beridze',
    customerPhone: '+995555111222',
    tableNumbers: [501],
    tableRefs: ['first/5'],
    reservationDate: '2026-09-20T00:00:00.000',
    reservationTime: '19:30',
    numberOfGuests: 4,
    notes: 'Window table please',
    status: 'confirmed',
    createdBy: 'Nino',
    isTakeAway: false,
    ...extra,
  };
}

describe('ReservationSyncService - a narrowed snapshot cleans the mirror', () => {
  it('keeps the bookings it is sent and reconciles the rest away', async () => {
    const h = makeService();
    // The mirror as a POS that sent everything left it.
    h.mirror.seed(
      { venueId: VENUE_A.venueId, posReservationId: 'real-future' },
      { venueId: VENUE_A.venueId, posReservationId: 'real-activated' },
      {
        venueId: VENUE_A.venueId,
        posReservationId: 'bk-walkin',
        notes: 'Order #1765',
        linkedOrderId: 1765,
      },
      {
        venueId: VENUE_A.venueId,
        posReservationId: 'bk-takeaway',
        isTakeAway: true,
      },
      {
        venueId: VENUE_A.venueId,
        posReservationId: 'bk-package',
        notes: 'Order #1767',
      },
    );

    await h.service.sync(VENUE_A, [
      booking('real-future'),
      booking('real-activated', { status: 'in-progress', linkedOrderId: 1770 }),
    ]);

    expect(h.mirror.idsFor(VENUE_A.venueId)).toEqual([
      'real-activated',
      'real-future',
    ]);
  });

  it('mirrors an activated booking as a booking, link and all', async () => {
    const h = makeService();

    await h.service.sync(VENUE_A, [
      booking('real-activated', { status: 'in-progress', linkedOrderId: 1770 }),
    ]);

    const row = h.mirror.rows.find(
      (r) => r.posReservationId === 'real-activated',
    );
    expect(row).toBeDefined();
    expect(row?.status).toBe('in-progress');
    expect(row?.linkedOrderId).toBe(1770);
    expect(row?.isTakeAway).toBe(false);
  });

  it('empties a Venue whose box holds only bookkeeping', async () => {
    const h = makeService();
    h.mirror.seed(
      { venueId: VENUE_A.venueId, posReservationId: 'bk-walkin' },
      { venueId: VENUE_A.venueId, posReservationId: 'bk-takeaway' },
    );

    await h.service.sync(VENUE_A, []);

    expect(h.mirror.idsFor(VENUE_A.venueId)).toEqual([]);
  });

  it('still says nothing when the snapshot omits reservations entirely', async () => {
    // An older POS build sends no field at all. Silence is not "no bookings",
    // and emptying the mirror over it would be the worst reading of it.
    const h = makeService();
    h.mirror.seed(
      { venueId: VENUE_A.venueId, posReservationId: 'real-future' },
      { venueId: VENUE_A.venueId, posReservationId: 'bk-walkin' },
    );

    await h.service.sync(VENUE_A, undefined);

    expect(h.mirror.idsFor(VENUE_A.venueId)).toEqual([
      'bk-walkin',
      'real-future',
    ]);
  });
});

describe('ReservationSyncService - one Venue cannot reconcile another', () => {
  it('leaves Venue B whole while Venue A is cleaned', async () => {
    const h = makeService();
    h.mirror.seed(
      { venueId: VENUE_A.venueId, posReservationId: 'a-real' },
      { venueId: VENUE_A.venueId, posReservationId: 'a-bookkeeping' },
      { venueId: VENUE_B.venueId, posReservationId: 'b-real' },
      { venueId: VENUE_B.venueId, posReservationId: 'b-bookkeeping' },
    );

    await h.service.sync(VENUE_A, [booking('a-real')]);

    expect(h.mirror.idsFor(VENUE_A.venueId)).toEqual(['a-real']);
    expect(h.mirror.idsFor(VENUE_B.venueId)).toEqual([
      'b-bookkeeping',
      'b-real',
    ]);
  });

  it('keeps a shared reservation id apart per Venue', async () => {
    const h = makeService();

    await h.service.sync(VENUE_A, [booking('shared', { numberOfGuests: 4 })]);
    await h.service.sync(VENUE_B, [booking('shared', { numberOfGuests: 9 })]);

    expect(h.mirror.rows).toHaveLength(2);
    expect(h.mirror.idsFor(VENUE_A.venueId)).toEqual(['shared']);
    expect(h.mirror.idsFor(VENUE_B.venueId)).toEqual(['shared']);
  });
});
