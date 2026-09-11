import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
const mockSend = jest.fn(async (_message: any) => ({
  failureCount: 0,
  responses: [],
}));
jest.mock('firebase-admin/app', () => ({ getApps: () => [{}] }));
jest.mock('firebase-admin/messaging', () => ({
  getMessaging: () => ({ sendEachForMulticast: mockSend }),
}));

import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import request from 'supertest';
import { Server } from 'socket.io';
import { PrismaService } from '../prisma.service';
import { AuthController } from '../auth/auth.controller';
import { AuthService } from '../auth/auth.service';
import { JwtStrategy } from '../auth/jwt.strategy';
import { ManagerTenantService } from '../auth/manager-tenant.service';
import { LoginThrottleService } from '../auth/login-throttle.service';
import { MobileController } from '../mobile/mobile.controller';
import { MobileUsersService } from '../mobile/services/mobile-users.service';
import { MobileReportsService } from '../mobile/services/mobile-reports.service';
import { MobileAuditLogService } from '../mobile/services/mobile-audit-log.service';
import { MobileDevicesService } from '../mobile/services/mobile-devices.service';
import { MobileMenuService } from '../mobile/services/mobile-menu.service';
import { MobileMutationSupport } from '../mobile/services/mobile-mutation-support.service';
import { MobileReservationsService } from '../mobile/services/mobile-reservations.service';
import { MobileDashboardService } from '../mobile/services/mobile-dashboard.service';
import { MobileOrdersService } from '../mobile/services/mobile-orders.service';
import { MobileSaleLedgerService } from '../mobile/services/mobile-sale-ledger.service';
import { InventoryService } from '../inventory/inventory.service';
import { SaleConsumptionService } from '../inventory/sale-consumption.service';
import { ReceivingService } from '../inventory/receiving.service';
import { RecipeService } from '../inventory/recipe.service';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { MonitoringGateway } from '../realtime/monitoring.gateway';
import { HybridNotificationService } from '../realtime/notifications/hybrid-notification.service';
import { PresenceService } from '../realtime/presence.service';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDb = databaseUrl ? describe : describe.skip;

describeDb('SaaS Manager: real PostgreSQL, HTTP and Socket.IO', () => {
  let prisma: PrismaService, auth: AuthService, resolver: ManagerTenantService;
  let gateway: MonitoringGateway,
    hybrid: HybridNotificationService,
    presence: PresenceService;
  let app: any, io: Server, url: string, jwt: JwtService;
  let organizationId: string;
  const venues: any[] = [],
    staff: any[] = [],
    tokens: string[] = [];
  const clients: any[] = [];
  const day = '2026-09-11';
  const oldSecret = process.env.JWT_SECRET;
  const oldDeadline = process.env.MANAGER_LEGACY_LOGIN_UNTIL;

  beforeAll(async () => {
    if (!databaseUrl?.includes('/manager_phase1'))
      throw new Error('Use a disposable manager_phase1 database');
    process.env.JWT_SECRET = 'disposable-manager-integration-secret';
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    organizationId = (
      await prisma.organization.create({ data: { name: 'Manager SaaS proof' } })
    ).id;
    const pinHash = await AuthService.hashPin('123456');
    const plan = await prisma.plan.findUniqueOrThrow({
      where: { key: 'POS_WEBSITE_MANAGER' },
    });
    for (const name of ['A', 'B']) {
      const venue = await prisma.venue.create({
        data: {
          organizationId,
          name,
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
        },
      });
      venues.push(venue);
      staff.push(
        await prisma.staff.create({
          data: {
            venueId: venue.id,
            username: 'manager',
            pinHash,
            role: 'MANAGER',
          },
        }),
      );
      await prisma.venuePlanAssignment.create({
        data: { venueId: venue.id, planId: plan.id },
      });
      await prisma.setting.create({
        data: { venueId: venue.id, key: 'currentBusinessDate', value: day },
      });
      await prisma.table.create({
        data: {
          venueId: venue.id,
          tableNumber: '1',
          floor: 'first',
          isReserved: true,
          currentBill: name === 'A' ? 10 : 20,
        },
      });
      await prisma.order.create({
        data: {
          venueId: venue.id,
          posOrderId: 1,
          status: 'confirmed',
          totalAmount: 10,
          waiterName: `secret-${name}`,
          businessDate: day,
        },
      });
      await prisma.expense.create({
        data: {
          venueId: venue.id,
          description: `secret-${name}`,
          amount: name === 'A' ? 11 : 22,
          category: 'other',
          businessDate: day,
        },
      });
      await prisma.stockItem.create({
        data: { venueId: venue.id, name: `secret-${name}`, baseUnit: 'kg' },
      });
    }
    jwt = new JwtService({ secret: process.env.JWT_SECRET });
    resolver = new ManagerTenantService(prisma);
    auth = new AuthService(prisma, jwt);
    presence = new PresenceService();
    gateway = new MonitoringGateway(jwt, presence, resolver, {} as never);
    hybrid = new HybridNotificationService(prisma, presence, gateway);
    (gateway as any).hybrid = hybrid;
    const ledger = new MobileSaleLedgerService(prisma);
    const module = await Test.createTestingModule({
      imports: [PassportModule.register({ defaultStrategy: 'jwt' })],
      controllers: [AuthController, MobileController],
      providers: [
        { provide: AuthService, useValue: auth },
        LoginThrottleService,
        { provide: ManagerTenantService, useValue: resolver },
        JwtStrategy,
        {
          provide: VenueEntitlementsService,
          useValue: new VenueEntitlementsService(prisma),
        },
        {
          provide: MobileDevicesService,
          useValue: new MobileDevicesService(prisma),
        },
        {
          provide: MobileOrdersService,
          useValue: new MobileOrdersService(
            prisma,
            gateway,
            {} as never,
            {} as never,
          ),
        },
        {
          provide: MobileDashboardService,
          useValue: new MobileDashboardService(
            prisma,
            gateway,
            {} as never,
            {} as never,
            ledger,
          ),
        },
        {
          provide: InventoryService,
          useValue: new InventoryService(prisma, {} as never),
        },
        { provide: MobileSaleLedgerService, useValue: ledger },
        ...[
          MobileUsersService,
          MobileReportsService,
          MobileAuditLogService,
          MobileMenuService,
          MobileMutationSupport,
          MobileReservationsService,
          SaleConsumptionService,
          ReceivingService,
          RecipeService,
        ].map((provide) => ({ provide, useValue: {} })),
      ],
    }).compile();
    app = module.createNestApplication();
    await app.init();
    io = new Server(app.getHttpServer());
    gateway.server = io;
    gateway.afterInit(io);
    io.on('connection', (socket) =>
      socket.on('disconnect', () => gateway.handleDisconnect(socket)),
    );
    await app.listen(0, '127.0.0.1');
    url = await app.getUrl();
    for (const venue of venues) {
      const result = await request(app.getHttpServer())
        .post('/auth/mobile-login')
        .send({ venueCode: venue.loginCode, pin: '123456' })
        .expect(200);
      tokens.push(result.body.access_token);
      expect(result.body).not.toHaveProperty('pin');
      expect(result.body.venueCode).toBe(venue.loginCode);
    }
  }, 30000);

  afterAll(async () => {
    clients.forEach((c) => c.close());
    if (io) await new Promise<void>((resolve) => io.close(() => resolve()));
    if (app) await app.close();
    if (prisma) {
      const where = { venueId: { in: venues.map((v) => v.id) } };
      for (const model of [
        'pushDevice',
        'managerNotification',
        'stockItem',
        'expense',
        'order',
        'table',
        'setting',
        'venuePlanAssignment',
        'staff',
      ] as const) {
        await (prisma[model] as any).deleteMany({ where });
      }
      await prisma.venue.deleteMany({
        where: { id: { in: venues.map((v) => v.id) } },
      });
      if (organizationId)
        await prisma.organization.delete({ where: { id: organizationId } });
      await prisma.$disconnect();
    }
    if (oldSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = oldSecret;
    if (oldDeadline === undefined)
      delete process.env.MANAGER_LEGACY_LOGIN_UNTIL;
    else process.env.MANAGER_LEGACY_LOGIN_UNTIL = oldDeadline;
  });

  const get = (index: number, path: string) =>
    request(app.getHttpServer())
      .get(path)
      .set('Authorization', `Bearer ${tokens[index]}`);

  it('resolves identical username/PIN credentials independently after Venue selection', async () => {
    for (let i = 0; i < 2; i++) {
      const claims = jwt.verify(tokens[i]);
      expect(claims.sub).toBe(staff[i].id);
      expect((await resolver.resolveByStaffId(claims.sub))?.venueId).toBe(
        venues[i].id,
      );
    }
    await request(app.getHttpServer())
      .post('/auth/mobile-login')
      .send({ venueCode: 'unknown-venue', pin: '123456' })
      .expect(401);
    // A PIN which exists only in A must not be usable with B's code.
    await prisma.staff.update({
      where: { id: staff[0].id },
      data: { pinHash: await AuthService.hashPin('654321') },
    });
    await expect(
      auth.mobileLogin('654321', venues[1].loginCode),
    ).rejects.toThrow();
    await prisma.staff.update({
      where: { id: staff[0].id },
      data: { pinHash: await AuthService.hashPin('123456') },
    });
    await expect(
      auth.mobileLogin('123456', venues[0].loginCode.toUpperCase()),
    ).resolves.toHaveProperty('access_token');
  });

  it('keeps public login codes unique and independent of the display name', async () => {
    expect(venues[0].loginCode).not.toBe(venues[1].loginCode);
    expect(venues[0].loginCode).not.toBe(venues[0].id);
    await prisma.venue.update({
      where: { id: venues[0].id },
      data: { name: 'Renamed restaurant' },
    });
    expect(
      (await prisma.venue.findUniqueOrThrow({ where: { id: venues[0].id } }))
        .loginCode,
    ).toBe(venues[0].loginCode);
    await expect(
      prisma.venue.create({
        data: {
          organizationId,
          name: 'Duplicate code',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          loginCode: venues[0].loginCode,
        },
      }),
    ).rejects.toMatchObject({ code: 'P2002' });
  });

  it('rejects ambiguous PINs within one Venue', async () => {
    const duplicate = await prisma.staff.create({
      data: {
        venueId: venues[0].id,
        username: 'another',
        role: 'MANAGER',
        pinHash: await AuthService.hashPin('123456'),
      },
    });
    await expect(
      auth.mobileLogin('123456', venues[0].loginCode),
    ).rejects.toThrow();
    await prisma.staff.delete({ where: { id: duplicate.id } });
  });

  it('re-resolves Staff and Venue on the next HTTP request, and denies disabled login', async () => {
    for (const target of ['staff', 'venue'] as const) {
      const model = prisma[target] as any;
      const id = target === 'staff' ? staff[0].id : venues[0].id;
      await model.update({
        where: { id },
        data: target === 'staff' ? { isActive: false } : { status: 'DISABLED' },
      });
      await get(0, '/mobile/tables').expect(401);
      await expect(
        auth.mobileLogin('123456', venues[0].loginCode),
      ).rejects.toThrow();
      await get(1, '/mobile/tables').expect(200);
      await model.update({
        where: { id },
        data: target === 'staff' ? { isActive: true } : { status: 'ACTIVE' },
      });
    }
  });

  it('isolates real Manager table, order, financial and inventory HTTP reads despite forged Venue hints', async () => {
    for (const i of [0, 1]) {
      const other = 1 - i;
      const hint = `?venueId=${venues[other].id}`;
      const tables = (await get(i, '/mobile/tables' + hint).expect(200)).body;
      expect(tables).toHaveLength(1);
      expect(tables[0].currentBill).toBe(i === 0 ? 10 : 20);
      for (const path of [
        '/mobile/orders',
        '/mobile/financials',
        '/mobile/inventory/stock-items',
      ]) {
        const result = (await get(i, path + hint).expect(200)).body;
        expect(JSON.stringify(result)).toContain(
          `secret-${i === 0 ? 'A' : 'B'}`,
        );
        expect(JSON.stringify(result)).not.toContain(
          `secret-${other === 0 ? 'A' : 'B'}`,
        );
      }
    }
    await get(0, '/sync/diff').expect(404);
  });

  // Speak Engine.IO/Socket.IO over an actual WebSocket, avoiding a test-only client dependency.
  async function connect(token: string) {
    const socket = new WebSocket(
      url.replace('http:', 'ws:') + '/socket.io/?EIO=4&transport=websocket',
    );
    const events: any[] = [];
    clients.push(socket);
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error('Socket handshake timeout')),
        3000,
      );
      socket.addEventListener('message', (event) => {
        const packet = String(event.data);
        if (packet.startsWith('0'))
          socket.send('40' + JSON.stringify({ token, venueId: venues[1].id }));
        if (packet === '2') socket.send('3');
        if (packet.startsWith('40')) {
          clearTimeout(timeout);
          resolve();
        }
        if (packet.startsWith('44')) {
          clearTimeout(timeout);
          reject(new Error('unauthorized'));
        }
        if (packet.startsWith('42')) events.push(JSON.parse(packet.slice(2)));
      });
    });
    return { socket, events };
  }
  const settle = () => new Promise((resolve) => setTimeout(resolve, 70));

  it('joins only the resolved room and delivers in both directions without cross-Venue leakage', async () => {
    const a = await connect(tokens[0]),
      b = await connect(tokens[1]);
    expect(io.sockets.adapter.rooms.has('managers')).toBe(false);
    expect(io.sockets.adapter.rooms.get(`managers:${venues[0].id}`)?.size).toBe(
      1,
    );
    for (const i of [0, 1]) {
      await gateway.emitEnvelope(
        {
          type: 'order_updated',
          payload: { secret: i },
          timestamp: new Date().toISOString(),
        },
        { venueId: venues[i].id },
      );
      await settle();
    }
    expect(
      a.events
        .filter((e) => e[0] === 'order_updated')
        .map((e) => e[1].payload.secret),
    ).toEqual([0]);
    expect(
      b.events
        .filter((e) => e[0] === 'order_updated')
        .map((e) => e[1].payload.secret),
    ).toEqual([1]);
    await prisma.staff.update({
      where: { id: staff[0].id },
      data: { isActive: false },
    });
    await gateway.emitEnvelope(
      { type: 'order_updated', payload: { secret: 'disabled' }, timestamp: '' },
      { venueId: venues[0].id },
    );
    await settle();
    expect(a.events.some((e) => e[1]?.payload?.secret === 'disabled')).toBe(
      false,
    );
    await expect(connect(tokens[0])).rejects.toThrow('unauthorized');
    await prisma.staff.update({
      where: { id: staff[0].id },
      data: { isActive: true },
    });
    b.socket.close();
    await settle();
  });

  it('scopes notification rows, delivery rows, presence and actual FCM recipient selection', async () => {
    presence.addSocket(venues[0].id, 'manager', 'presence-proof');
    expect(presence.getOnlineStaffUsernames(venues[1].id).has('manager')).toBe(
      false,
    );
    presence.removeSocket('presence-proof');
    mockSend.mockClear();
    for (const i of [0, 1]) {
      await request(app.getHttpServer())
        .post('/mobile/push/register')
        .set('Authorization', `Bearer ${tokens[i]}`)
        .send({ fcmToken: `device-${i}`, venueId: venues[1 - i].id })
        .expect(201);
      await hybrid.deliver(
        'day_closed',
        { date: day },
        { venueId: venues[i].id },
      );
      const rows = await prisma.managerNotification.findMany({
        where: { venueId: venues[i].id },
        include: { deliveries: true },
      });
      expect(rows).toHaveLength(1);
      expect(rows[0].deliveries).toEqual([
        expect.objectContaining({ staffUsername: 'manager', channel: 'FCM' }),
      ]);
      const replay = (await get(i, '/mobile/notifications').expect(200)).body;
      expect(replay.map((r: any) => r.id)).toEqual([rows[0].id]);
      expect(mockSend.mock.calls[i][0].tokens).toEqual([`device-${i}`]);
    }
    // Re-login moves the globally unique handset token; stale logout cannot delete it.
    const devices = new MobileDevicesService(prisma);
    await devices.registerPushDevice(
      { venueId: venues[1].id, organizationId },
      'manager',
      { fcmToken: 'device-0' },
    );
    await devices.unregisterPushDevice(
      { venueId: venues[0].id, organizationId },
      'manager',
      { fcmToken: 'device-0' },
    );
    mockSend.mockClear();
    await hybrid.deliver(
      'day_closed',
      { date: day },
      { venueId: venues[0].id },
    );
    expect(mockSend).not.toHaveBeenCalled();
    await hybrid.deliver(
      'day_closed',
      { date: day },
      { venueId: venues[1].id },
    );
    expect(new Set(mockSend.mock.calls[0][0].tokens)).toEqual(
      new Set(['device-0', 'device-1']),
    );
  });

  it('keeps Vankisi PIN-only compatibility explicitly bounded and disabled by default', async () => {
    const venue = await prisma.venue.findUniqueOrThrow({
      where: { loginCode: 'vankisi' },
    });
    const manager = await prisma.staff.create({
      data: {
        venueId: venue.id,
        username: 'compatibility-proof',
        pinHash: await AuthService.hashPin('987654'),
        role: 'MANAGER',
      },
    });
    const now = jest
      .spyOn(Date, 'now')
      .mockReturnValue(Date.parse('2026-09-11T00:00:00Z'));
    try {
      delete process.env.MANAGER_LEGACY_LOGIN_UNTIL;
      await expect(auth.mobileLogin('987654')).rejects.toThrow();
      process.env.MANAGER_LEGACY_LOGIN_UNTIL = '2026-10-01T00:00:00Z';
      expect(
        jwt.verify((await auth.mobileLogin('987654')).access_token).sub,
      ).toBe(manager.id);
      process.env.MANAGER_LEGACY_LOGIN_UNTIL = '2026-09-01T00:00:00Z';
      await expect(auth.mobileLogin('987654')).rejects.toThrow();
      process.env.MANAGER_LEGACY_LOGIN_UNTIL = '2027-01-01T00:00:00Z';
      await expect(auth.mobileLogin('987654')).rejects.toThrow();
      await expect(
        auth.mobileLogin('987654', 'vankisi'),
      ).resolves.toHaveProperty('access_token');
    } finally {
      now.mockRestore();
      await prisma.staff.delete({ where: { id: manager.id } });
    }
  });
});
