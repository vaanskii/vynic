jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { WebsiteMode } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { TenantContext } from './tenant-context';
import { FeatureKeys } from '../entitlements/feature-keys';
import { FeatureGuard } from '../entitlements/feature.guard';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { MenuService } from '../website/menu/menu.service';
import { PosReservationMirrorService } from '../pos/pos-reservation-mirror.service';
import { ReservationService } from '../website/reservation/reservation.service';
import { WebsitePosReservationBridgeService } from '../website/reservation/website-pos-reservation-bridge.service';
import { UserService } from '../website/user/user.service';
import { WebsiteTenantService } from '../website/tenancy/website-tenant.service';
import { TableSyncService } from '../pos/sync/snapshot/table-sync.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('Public website tenant isolation (PostgreSQL)', () => {
  let prisma: PrismaService;
  let websiteTenant: WebsiteTenantService;
  let entitlements: VenueEntitlementsService;
  let menu: MenuService;
  let reservations: ReservationService;
  let users: UserService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `70000000-0000-4000-8000-${suffix}`;
  // A and B both sell a website. C bought POS only.
  const venueAId = `71000000-0000-4000-8000-${suffix}`;
  const venueBId = `72000000-0000-4000-8000-${suffix}`;
  const venueCId = `73000000-0000-4000-8000-${suffix}`;
  const venueIds = [venueAId, venueBId, venueCId];

  const hostA = `a-${suffix}.test`;
  const hostB = `b-${suffix}.test`;
  const hostC = `c-${suffix}.test`;

  const tenantA: TenantContext = { venueId: venueAId, organizationId };
  const tenantB: TenantContext = { venueId: venueBId, organizationId };

  const bookingDate = '2026-09-14';

  async function planId(key: string) {
    return (await prisma.plan.findUniqueOrThrow({ where: { key } })).id;
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();

    entitlements = new VenueEntitlementsService(prisma);
    // Production resolves the host header; the fallback is irrelevant here
    // because every fixture host is registered.
    websiteTenant = new WebsiteTenantService(prisma, {
      get: (key: string) => (key === 'NODE_ENV' ? 'production' : undefined),
    } as never);
    menu = new MenuService(prisma);
    // Reservation reads come from the Cloud mirror since Step 6C, so this is a
    // real service over the same PostgreSQL — an empty mirror means "no POS
    // bookings", which is the behaviour being relied on here.
    const bridge = new WebsitePosReservationBridgeService(
      prisma,
      {} as never, // gateway — only reached when pushing to POS
      menu,
      new PosReservationMirrorService(prisma),
      {} as never, // posCommands — only reached when pushing to POS
    );
    reservations = new ReservationService(
      prisma,
      // Payment is a separate concern; an order that returns nothing leaves the
      // booking PENDING, exactly as an unpaid booking is today.
      { createOrder: () => Promise.resolve(null) } as never,
      bridge,
    );
    users = new UserService(prisma);

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });
    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Public isolation fixture',
        venues: {
          create: [
            venue(venueAId, 'Venue A'),
            venue(venueBId, 'Venue B'),
            venue(venueCId, 'Venue C'),
          ],
        },
      },
    });

    await prisma.venuePlanAssignment.createMany({
      data: [
        { venueId: venueAId, planId: await planId('POS_WEBSITE') },
        { venueId: venueBId, planId: await planId('POS_WEBSITE') },
        // POS only: Venue C never bought a website.
        { venueId: venueCId, planId: await planId('POS') },
      ],
    });
    await prisma.venueWebsiteConfig.createMany({
      data: [
        { venueId: venueAId, mode: WebsiteMode.CUSTOM },
        { venueId: venueBId, mode: WebsiteMode.SAAS },
        { venueId: venueCId, mode: WebsiteMode.NONE },
      ],
    });
    await prisma.venueDomain.createMany({
      data: [
        { venueId: venueAId, hostname: hostA },
        { venueId: venueBId, hostname: hostB },
        { venueId: venueCId, hostname: hostC },
      ],
    });

    // Deliberately colliding labels: the same category slug, the same website
    // table number, the same POS table on the same floor.
    for (const [venueId, price] of [
      [venueAId, 12],
      [venueBId, 99],
    ] as const) {
      await prisma.menuCategory.create({
        data: {
          venueId,
          slug: 'wine',
          nameEn: venueId === venueAId ? 'A Wine' : 'B Wine',
          nameKa: 'ღვინო',
          items: {
            create: [
              {
                venueId,
                nameEn: venueId === venueAId ? 'A Saperavi' : 'B Saperavi',
                nameKa: 'საფერავი',
                price,
              },
            ],
          },
        },
      });
      await prisma.websiteTable.createMany({
        data: [
          {
            venueId,
            websiteTableNumber: 'table1',
            posTableNumber: '1',
            posFloor: 'first',
            capacity: 2,
          },
          {
            venueId,
            websiteTableNumber: 'table2',
            posTableNumber: '2',
            posFloor: 'first',
            capacity: 4,
          },
        ],
      });
    }
  });

  afterAll(async () => {
    await prisma.websiteReservation.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.websiteTable.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.menuItem.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.menuCategory.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.table.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venueDomain.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venueWebsiteConfig.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venuePlanAssignment.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.delete({ where: { id: organizationId } });
    await prisma.$disconnect();
  });

  describe('the host resolves the tenant', () => {
    it('gives each hostname its own Venue and Organization', async () => {
      await expect(
        websiteTenant.resolveRequest({ headers: { host: hostA } }),
      ).resolves.toEqual({
        tenant: tenantA,
        hostname: hostA,
        configuredMode: WebsiteMode.CUSTOM,
      });
      await expect(
        websiteTenant.resolveRequest({ headers: { host: `${hostB}:443` } }),
      ).resolves.toMatchObject({
        tenant: tenantB,
        configuredMode: WebsiteMode.SAAS,
      });
    });

    it('serves no Venue for an unregistered host', async () => {
      await expect(
        websiteTenant.resolveRequest({
          headers: { host: `nobody-${suffix}.test` },
        }),
      ).resolves.toBeNull();
    });

    it('stops serving a disabled domain and resumes when re-enabled', async () => {
      await prisma.venueDomain.update({
        where: { hostname: hostB },
        data: { status: 'DISABLED' },
      });
      await expect(websiteTenant.resolveByHostname(hostB)).resolves.toBeNull();

      await prisma.venueDomain.update({
        where: { hostname: hostB },
        data: { status: 'ACTIVE' },
      });
      await expect(
        websiteTenant.resolveByHostname(hostB),
      ).resolves.not.toBeNull();
    });

    it('refuses to let one hostname name two Venues', async () => {
      await expect(
        prisma.venueDomain.create({
          data: { venueId: venueCId, hostname: hostA },
        }),
      ).rejects.toMatchObject({ code: 'P2002' });
    });
  });

  describe('Venue A website cannot see Venue B', () => {
    it('reads only its own menu, despite the same category slug', async () => {
      const [categoryA] = await menu.getAllCategories(tenantA);
      const [categoryB] = await menu.getAllCategories(tenantB);

      expect(categoryA.nameEn).toBe('A Wine');
      expect(categoryB.nameEn).toBe('B Wine');
      expect(
        (await menu.getCategoryBySlug(tenantA, 'wine')).items[0].price,
      ).toBe(12);
      expect(
        (await menu.getCategoryBySlug(tenantB, 'wine')).items[0].price,
      ).toBe(99);
    });

    it('cannot price a cart from another Venue menu item', async () => {
      const foreign = await prisma.menuItem.findFirstOrThrow({
        where: { venueId: venueBId },
      });
      await expect(
        menu.getMenuItemById(tenantA, foreign.id),
      ).resolves.toBeNull();
      await expect(
        menu.getMenuItemById(tenantB, foreign.id),
      ).resolves.not.toBeNull();
    });

    it('lets both Venues publish the same website table number', async () => {
      const numbers = async (tenant: TenantContext) =>
        (await reservations.getAllTables(tenant))
          .map((table) => table.tableNumber)
          .sort();

      expect(await numbers(tenantA)).toEqual(['table1', 'table2']);
      expect(await numbers(tenantB)).toEqual(['table1', 'table2']);

      const idsA = (await reservations.getAllTables(tenantA)).map((t) => t.id);
      const idsB = (await reservations.getAllTables(tenantB)).map((t) => t.id);
      expect(idsA).not.toEqual(expect.arrayContaining(idsB));
    });

    it('refuses a duplicate website table number inside one Venue', async () => {
      await expect(
        prisma.websiteTable.create({
          data: {
            venueId: venueAId,
            websiteTableNumber: 'table1',
            posTableNumber: '7',
            posFloor: 'first',
          },
        }),
      ).rejects.toMatchObject({ code: 'P2002' });
    });
  });

  describe('bookings belong to the Venue that took them', () => {
    it('creates a booking against the resolved Venue only', async () => {
      const created = await reservations.createReservation(tenantA, {
        selectedTables: ['table1'],
        selectedDate: bookingDate,
        selectedTime: '19:00',
        customerName: 'Guest A',
      });

      expect(created.reservation.status).toBe('PENDING');
      const stored = await prisma.websiteReservation.findUniqueOrThrow({
        where: { id: created.reservation.id },
        include: { tables: { include: { table: true } } },
      });
      expect(stored.venueId).toBe(venueAId);
      expect(stored.tables[0].table.venueId).toBe(venueAId);
    });

    it('cannot book a table that belongs to another Venue', async () => {
      // Venue B has no `f2-table1`; Venue A does. Asking for it on B's site is
      // simply an unknown table, never a cross-tenant booking.
      await prisma.websiteTable.create({
        data: {
          venueId: venueAId,
          websiteTableNumber: 'f2-table1',
          posTableNumber: '1',
          posFloor: 'second',
          capacity: 4,
        },
      });

      await expect(
        reservations.createReservation(tenantB, {
          selectedTables: ['f2-table1'],
          selectedDate: bookingDate,
          selectedTime: '19:00',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('keeps each Venue booking list to itself', async () => {
      await reservations.createReservation(tenantB, {
        selectedTables: ['table2'],
        selectedDate: bookingDate,
        selectedTime: '20:00',
        customerName: 'Guest B',
      });

      const namesA = (
        await reservations.getReservationsForDate(tenantA, bookingDate)
      ).map((row) => row.customerName);
      const namesB = (
        await reservations.getReservationsForDate(tenantB, bookingDate)
      ).map((row) => row.customerName);

      expect(namesA).toEqual(['Guest A']);
      expect(namesB).toEqual(['Guest B']);
    });

    it('blocks a slot only on the Venue that booked it', async () => {
      const availability = async (tenant: TenantContext) =>
        Object.fromEntries(
          (await reservations.getTableAvailability(tenant, bookingDate)).map(
            (row) => [row.tableNumber, row.bookedTimeSlots],
          ),
        );

      expect(await availability(tenantA)).toMatchObject({
        table1: ['19:00'],
        table2: [],
      });
      expect(await availability(tenantB)).toMatchObject({
        table1: [],
        table2: ['20:00'],
      });
    });

    it('shows a customer only the bookings made at this restaurant', async () => {
      const customer = await prisma.websiteUser.create({
        data: {
          phone: `+99555${suffix.slice(-6)}`,
          password: 'not-a-real-hash',
          email: `guest-${suffix}@example.test`,
        },
      });
      await prisma.websiteReservation.updateMany({
        where: { venueId: { in: [venueAId, venueBId] } },
        data: { userId: customer.id, status: 'CONFIRMED' },
      });

      const seenFromA = await users.getUserReservations(tenantA, customer.id);
      const seenFromB = await users.getUserReservations(tenantB, customer.id);

      expect(seenFromA).toHaveLength(1);
      expect(seenFromB).toHaveLength(1);
      expect(seenFromA[0].id).not.toBe(seenFromB[0].id);

      await prisma.websiteReservation.updateMany({
        where: { venueId: { in: [venueAId, venueBId] } },
        data: { userId: null, status: 'PENDING' },
      });
      await prisma.websiteUser.delete({ where: { id: customer.id } });
    });

    it('lets two Venues carry the same POS reservation id', async () => {
      const [bookingA, bookingB] = await Promise.all([
        prisma.websiteReservation.findFirstOrThrow({
          where: { venueId: venueAId },
        }),
        prisma.websiteReservation.findFirstOrThrow({
          where: { venueId: venueBId },
        }),
      ]);

      await prisma.websiteReservation.update({
        where: { id: bookingA.id },
        data: { posReservationId: '42' },
      });
      await prisma.websiteReservation.update({
        where: { id: bookingB.id },
        data: { posReservationId: '42' },
      });

      expect(
        await prisma.websiteReservation.count({
          where: { posReservationId: '42' },
        }),
      ).toBe(2);
    });

    it('resolves the payment tenant from the booking, not from a host', async () => {
      const booking = await prisma.websiteReservation.findFirstOrThrow({
        where: { venueId: venueBId },
        include: { venue: { select: { organizationId: true } } },
      });

      // This is the whole authority a BOG callback has: a provider reference
      // naming a reservation, and a reservation naming its Venue.
      expect({
        venueId: booking.venueId,
        organizationId: booking.venue.organizationId,
      }).toEqual(tenantB);
    });
  });

  describe('WEBSITE entitlement', () => {
    it('is held by the website Venues and not by the POS-only one', async () => {
      await expect(
        entitlements.hasFeature(venueAId, FeatureKeys.WEBSITE),
      ).resolves.toBe(true);
      await expect(
        entitlements.hasFeature(venueCId, FeatureKeys.WEBSITE),
      ).resolves.toBe(false);
    });

    it('denies the website product to the POS-only Venue', async () => {
      const guard = makeFeatureGuard();

      await expect(guard(venueCId)).rejects.toBeInstanceOf(ForbiddenException);
      await expect(guard(venueAId)).resolves.toBe(true);
      await expect(guard(venueBId)).resolves.toBe(true);
    });

    it('reports the effective mode as NONE for an unentitled Venue', async () => {
      await expect(entitlements.websiteAccess(venueCId)).resolves.toEqual({
        entitled: false,
        configuredMode: WebsiteMode.NONE,
        effectiveMode: WebsiteMode.NONE,
        consistent: true,
      });
      await expect(entitlements.websiteAccess(venueAId)).resolves.toEqual({
        entitled: true,
        configuredMode: WebsiteMode.CUSTOM,
        effectiveMode: WebsiteMode.CUSTOM,
        consistent: true,
      });
    });

    it('treats CUSTOM and SAAS the same way at the tenant boundary', async () => {
      // The two modes differ in how a site is built and served, never in how
      // its Venue is established or entitled.
      const a = await websiteTenant.resolveByHostname(hostA);
      const b = await websiteTenant.resolveByHostname(hostB);

      expect(a!.configuredMode).toBe(WebsiteMode.CUSTOM);
      expect(b!.configuredMode).toBe(WebsiteMode.SAAS);
      await expect(makeFeatureGuard()(a!.tenant.venueId)).resolves.toBe(true);
      await expect(makeFeatureGuard()(b!.tenant.venueId)).resolves.toBe(true);
    });
  });

  it('keeps POS sync working for the Venue that never bought a website', async () => {
    await expect(
      entitlements.hasFeature(venueCId, FeatureKeys.WEBSITE),
    ).resolves.toBe(false);

    await new TableSyncService(prisma).sync(
      { venueId: venueCId, organizationId },
      [
        {
          tableNumber: '4',
          floor: 'first',
          isReserved: false,
          activeOrderId: null,
          currentBill: 0,
        },
      ],
      false,
    );

    expect(await prisma.table.count({ where: { venueId: venueCId } })).toBe(1);
  });

  /** The guard the public website controllers carry, driven as Nest drives it. */
  function makeFeatureGuard() {
    const reflector = {
      getAllAndOverride: () => FeatureKeys.WEBSITE,
    } as never;
    const guard = new FeatureGuard(reflector, entitlements);
    return (venueId: string) =>
      guard.canActivate({
        getHandler: () => () => undefined,
        getClass: () => class {},
        switchToHttp: () => ({
          getRequest: () => ({
            websiteTenant: { venueId, organizationId },
          }),
        }),
      } as never);
  }
});
