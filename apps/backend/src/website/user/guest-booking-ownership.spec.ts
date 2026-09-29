jest.mock('../../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { Prisma, WebsiteUser } from '@prisma/client';
import type { PrismaService } from '../../prisma.service';
import type { TenantContext } from '../../tenancy/tenant-context';
import { WebsiteAuthService } from '../auth/auth.service';
import { BogController } from '../payment/payment.controller';
import type { BogService } from '../payment/payment.service';
import type { ReservationService } from '../reservation/reservation.service';
import { UserController } from './user.controller';
import { UserService } from './user.service';

const tenant: TenantContext = { venueId: 'venue-a', organizationId: 'org-a' };
const victimEmail = 'victim@example.invalid';

function fixture() {
  let account: WebsiteUser | null = null;
  const rows = [
    {
      id: 'victim-guest',
      venueId: tenant.venueId,
      userId: null as string | null,
      customerEmail: victimEmail,
      customerName: 'Private guest',
      customerPhone: 'Private phone',
      notes: 'Private notes',
      menuItems: JSON.stringify([{ id: 'meal', quantity: 1, price: 10 }]),
      date: new Date('2026-12-01'),
      createdAt: new Date('2026-01-01'),
      timeSlot: '18:00',
      status: 'CONFIRMED',
      totalAmount: 11,
      tables: [{ table: { websiteTableNumber: 'table1', capacity: 4 } }],
    },
  ];
  const findReservations = jest.fn(
    ({ where }: Prisma.WebsiteReservationFindManyArgs) =>
      Promise.resolve(
        rows.filter(
          (row) =>
            row.venueId === where?.venueId &&
            (where?.userId === row.userId ||
              where?.OR?.some(
                (clause) =>
                  clause.userId === row.userId ||
                  (Array.isArray(clause.AND) && row.userId === null),
              )) &&
            ['CONFIRMED', 'COMPLETED'].includes(row.status),
        ),
      ),
  );
  const menuRead = jest.fn(() =>
    Promise.resolve([{ id: 'meal', nameEn: 'Meal', price: 10 }]),
  );
  const prisma = {
    websiteUser: {
      create: jest.fn(({ data }: { data: Partial<WebsiteUser> }) => {
        account = { id: 'attacker', ...data } as WebsiteUser;
        return Promise.resolve(account);
      }),
      update: jest.fn(() => Promise.resolve(account)),
      findUnique: jest.fn(() => Promise.resolve(account)),
    },
    websiteReservation: { findMany: findReservations },
    menuItem: { findMany: menuRead },
  };
  const db = prisma as unknown as PrismaService;
  const auth = new WebsiteAuthService(
    db,
    new JwtService(),
    new ConfigService({
      JWT_SECRET: 'sec02-unit-access',
      JWT_REFRESH_SECRET: 'sec02-unit-refresh',
    }),
    {} as never,
  );
  const users = new UserService(db);
  return {
    rows,
    users,
    auth,
    findReservations,
    menuRead,
    signup: () =>
      auth.signup({
        phone: 'synthetic-phone',
        email: victimEmail,
        password: 'synthetic-password',
      }),
  };
}

describe('SEC-02 guest booking ownership', () => {
  it('unverified victim-email signup cannot read the guest booking or its private fields', async () => {
    const f = fixture();
    await f.signup();
    const before = structuredClone(f.rows);
    expect(await f.users.getUserReservations(tenant, 'attacker')).toEqual([]);
    expect(f.menuRead).not.toHaveBeenCalled();
    expect(f.rows).toEqual(before);
  });

  it('constrains ownership in the database query before projecting any rows', async () => {
    const f = fixture();
    await f.signup();
    await f.users.getUserReservations(tenant, 'attacker');
    expect(f.findReservations).toHaveBeenCalledWith({
      where: {
        venueId: tenant.venueId,
        userId: 'attacker',
        status: { in: ['CONFIRMED', 'COMPLETED'] },
      },
      include: { tables: { include: { table: true } } },
      orderBy: { date: 'desc' },
    });
  });

  it.each(['CONFIRMED', 'COMPLETED'])(
    'preserves an existing user-bound %s booking even when contact email differs',
    async (status) => {
      const f = fixture();
      await f.signup();
      Object.assign(f.rows[0], {
        userId: 'attacker',
        status,
        customerEmail: 'different-contact@example.invalid',
      });
      const result = await f.users.getUserReservations(tenant, 'attacker');
      expect(result).toHaveLength(1);
      expect(result[0]).toMatchObject({
        id: 'victim-guest',
        customerEmail: 'different-contact@example.invalid',
        notes: 'Private notes',
        menuItems: [{ id: 'meal', quantity: 1, price: 10, name: 'Meal' }],
      });
    },
  );

  it('does not return another user-bound booking with the same contact email', async () => {
    const f = fixture();
    await f.signup();
    f.rows[0].userId = 'other-account';
    expect(await f.users.getUserReservations(tenant, 'attacker')).toEqual([]);
  });

  it.each([null, 'attacker'])(
    'does not return a foreign-Venue booking bound to %s',
    async (userId) => {
      const f = fixture();
      await f.signup();
      Object.assign(f.rows[0], { userId, venueId: 'venue-b' });
      expect(await f.users.getUserReservations(tenant, 'attacker')).toEqual([]);
    },
  );

  it.each(['PENDING', 'FAILED', 'CANCELLED'])(
    'preserves the existing list status policy for %s',
    async (status) => {
      const f = fixture();
      await f.signup();
      Object.assign(f.rows[0], { userId: 'attacker', status });
      expect(await f.users.getUserReservations(tenant, 'attacker')).toEqual([]);
    },
  );

  it('uses the authenticated request ID, ignoring body and email identity claims', async () => {
    const read = jest.fn(() => Promise.resolve([]));
    const controller = new UserController({
      getUserReservations: read,
    } as unknown as UserService);
    await controller.getUserReservations(tenant, {
      user: { id: 'session-user', email: victimEmail },
      body: { userId: 'victim', venueId: 'venue-b' },
    } as never);
    expect(read).toHaveBeenCalledWith(tenant, 'session-user');
  });
});

describe('SEC-02 payment status is not reservation ownership', () => {
  it.each(['completed', 'rejected', 'pending'])(
    'returns only a status for provider outcome %s, never the private booking row',
    async (status) => {
      const update = jest.fn(() => Promise.resolve(fixture().rows[0]));
      const controller = new BogController(
        {
          getPaymentDetails: () =>
            Promise.resolve({ external_order_id: 'victim-guest', status }),
        } as unknown as BogService,
        {
          updateReservationPaymentStatus: update,
        } as unknown as ReservationService,
        {} as WebsiteAuthService,
      );
      const result = await controller.checkOrderStatus(tenant, 'provider-id');
      expect(Object.keys(result).sort()).toEqual(['status', 'success']);
      expect(update).toHaveBeenCalledTimes(1);
    },
  );
});
