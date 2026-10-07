import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => jest.requireActual<typeof import('node:crypto')>('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma.service';
import { MobileController } from '../mobile.controller';
import { MobileDashboardService } from './mobile-dashboard.service';
import { requestTableRepair } from './manager-table-repair';
import { JwtStrategy } from '../../auth/jwt.strategy';
import { ManagerTenantService } from '../../auth/manager-tenant.service';
import { VenueEntitlementsService } from '../../entitlements/venue-entitlements.service';
import { EdgeTransportController } from '../../edge/edge-transport.controller';
import { EdgeCommandService } from '../../edge/edge-command.service';
import { onboardingApp } from '../../../test/onboarding-app.fixture';
import { seedMenu03 } from '../../../test/menu03.fixture';
import { isFreshDisposableDatabase } from '../../../test/disposable-database';
import { InventoryService } from '../../inventory/inventory.service';
import { SaleConsumptionService } from '../../inventory/sale-consumption.service';
import { DeviceCredentialService } from '../../auth/device-credential.service';
import type { ManagerAuthContext } from '../../auth/manager-auth-context';

const url = process.env.MGR02_TEST_DATABASE_URL;
const integration = url ? describe : describe.skip;
integration('MGR02 real guarded HTTP/PostgreSQL repair lifecycle', () => {
  let db: PrismaService;
  let app: Awaited<ReturnType<typeof onboardingApp>>;
  let base: string;
  let seeded: Awaited<ReturnType<typeof seedMenu03>>;
  let actor: ManagerAuthContext;
  let token: string;
  let tableId: string;
  let deviceId: string;
  let requestId: string;
  const post = async (path: string, body: unknown, auth = token, edge = false) => {
    const r = await fetch(base + path, { method: 'POST', headers: {
      'Content-Type': 'application/json', ...(auth ? edge ? {'X-POS-Sync-Key': auth} : {Authorization: `Bearer ${auth}`} : {}),
    }, body: JSON.stringify(body) });
    return { status: r.status, body: await r.json() as any };
  };
  const repair = (body: unknown = {requestId}, auth = token, floor = 'first') =>
    post(`/mobile/tables/7/free?floor=${floor}`, body, auth);
  async function claim() {
    const response = await post('/edge/commands/claim', {acceptedContractVersions:[2,1]}, seeded.venues[0].credential, true);
    expect(response.status).toBe(201); return response.body.commands;
  }
  const ack = (id: string, status = 'SUCCEEDED', code = 'table_repaired', credential = seeded.venues[0].credential) =>
    post('/edge/commands/ack', {commandId:id, status, code}, credential, true);
  beforeAll(async () => {
    if (!url || !isFreshDisposableDatabase(url)) throw Error('Fresh disposable MGR02 database required');
    process.env.JWT_SECRET = 'mgr02-synthetic-test-only-signing';
    process.env.COOKIE_ENCRYPTION_KEY = 'mgr02-synthetic-test-only-cookie';
    db = new PrismaService({ datasourceUrl: url });
    const controllerDependencies: any[] = Reflect.getMetadata('design:paramtypes', MobileController);
    const unused = controllerDependencies.filter((type) => type !== VenueEntitlementsService).map((type) => ({
      provide: type, useValue: type === MobileDashboardService
        ? new MobileDashboardService(db, {} as any, {} as any, {} as any) : {},
    }));
    app = await onboardingApp(db, undefined, {
      controllers: [MobileController, EdgeTransportController],
      providers: [...unused, JwtStrategy, ManagerTenantService,
        {provide: InventoryService, useValue:{}}, {provide: SaleConsumptionService, useValue:{}}],
    });
    await app.listen(0, '127.0.0.1'); base = await app.getUrl();
    seeded = await seedMenu03(db, app);
    const feature = await db.feature.upsert({where:{key:'MANAGER_APP'}, update:{}, create:{key:'MANAGER_APP',name:'Synthetic Manager'}});
    for (const v of seeded.venues) {
      const assignment = await db.venuePlanAssignment.findUniqueOrThrow({where:{venueId:v.venueId}});
      await db.planFeature.upsert({where:{planId_featureId:{planId:assignment.planId,featureId:feature.id}}, update:{}, create:{planId:assignment.planId,featureId:feature.id}});
      const staff = await db.staff.create({data:{venueId:v.venueId, username:`manager-${randomUUID()}`,role:'MANAGER',pinHash:'unused-synthetic-only'}});
      if (v === seeded.venues[0]) {
        const venue = await db.venue.findUniqueOrThrow({where:{id:v.venueId}});
        actor = {venueId:v.venueId,organizationId:venue.organizationId,staffId:staff.id,username:staff.username,role:'MANAGER'};
        token = new JwtService().sign({sub:staff.id,username:'ignored',role:'WAITER',venueId:seeded.venues[1].venueId},{secret:process.env.JWT_SECRET});
      }
    }
    deviceId = seeded.venues[0].credential.split('.')[1];
    await db.venue.update({where:{id:actor.venueId},data:{activeOperationalDeviceId:deviceId}});
    tableId = randomUUID();
    await db.table.create({data:{id:tableId,venueId:actor.venueId,tableNumber:'7',floor:'first',isReserved:true,activeOrderId:999,currentBill:55}});
  }, 60000);
  beforeEach(async () => {
    requestId = randomUUID();
    await db.edgeCommand.deleteMany({where:{venueId:actor.venueId}});
    await db.table.update({where:{id:tableId},data:{isReserved:true,activeOrderId:999,currentBill:55}});
    await db.venue.update({where:{id:actor.venueId},data:{activeOperationalDeviceId:deviceId}});
  });
  afterAll(async () => { await app?.close(); await db?.$disconnect(); });
  test('offline acceptance is202, one selected primary command, and unchanged mirror', async () => {
    const r = await repair(); expect(r.status).toBe(202);
    expect(r.body.success).toBe(false); expect(r.body.posDelivery.status).toBe('QUEUED');
    const command = await db.edgeCommand.findUniqueOrThrow({where:{id:r.body.posDelivery.commandId}});
    expect(command.deviceId).toBe(deviceId); expect(command.venueId).toBe(actor.venueId);
    expect((command.payload as any).actorStaffId).toBe(actor.staffId);
    const table = await db.table.findUniqueOrThrow({where:{id:tableId}});
    expect(table.activeOrderId).toBe(999); expect(table.currentBill).toBe(55);
  });
  test('no enrolled selected primary isUNAVAILABLE, with no callback/mirror/queue write', async () => {
    await db.venue.update({where:{id:actor.venueId},data:{activeOperationalDeviceId:null}});
    const r = await repair(); expect(r.body.posDelivery.status).toBe('UNAVAILABLE'); expect(r.body.accepted).toBe(false);
    expect(await db.edgeCommand.count()).toBe(0);
    expect((await db.table.findUniqueOrThrow({where:{id:tableId}})).isReserved).toBe(true);
  });
  test('missingtable is404; oldemptybody, malformedUUID and repeatedfloor are400', async () => {
    expect((await post('/mobile/tables/missing/free?floor=first',{requestId})).status).toBe(404);
    expect((await repair({})).status).toBe(400);
    expect((await repair({requestId:'bad'})).status).toBe(400);
    expect((await repair({requestId},token,'first&floor=second')).status).toBe(400);
    expect(await db.edgeCommand.count()).toBe(0);
  });
  test('unsignedrequest is401 and clienttenant/actor fields cannot widen authority', async () => {
    expect((await repair({requestId},'')).status).toBe(401);
    const r = await repair({requestId,venueId:seeded.venues[1].venueId,actorStaffId:randomUUID()});
    expect(r.status).toBe(202);
    const row = await db.edgeCommand.findUniqueOrThrow({where:{id:r.body.posDelivery.commandId}});
    expect(row.venueId).toBe(actor.venueId); expect((row.payload as any).actorStaffId).toBe(actor.staffId);
  });
  test('deactivated Manager is rejected using currentStaff instead of old tokenclaims', async () => {
    await db.staff.update({where:{id:actor.staffId},data:{isActive:false}});
    try { expect((await repair()).status).toBe(401); expect(await db.edgeCommand.count()).toBe(0); }
    finally { await db.staff.update({where:{id:actor.staffId},data:{isActive:true}}); }
  });
  test('concurrent lost-response retries retain one immutable command', async () => {
    const outcomes = await Promise.all(Array.from({length:12},()=>repair()));
    expect(new Set(outcomes.map((r)=>r.body.posDelivery.commandId)).size).toBe(1);
    expect(await db.edgeCommand.count()).toBe(1);
    const before = await db.edgeCommand.findFirstOrThrow();
    await db.table.update({where:{id:tableId},data:{activeOrderId:888}});
    await repair(); const after = await db.edgeCommand.findFirstOrThrow();
    expect(after.payload).toEqual(before.payload);
    expect(after.attemptCount).toBe(before.attemptCount);
    expect((await post('/mobile/tables/other/free?floor=first',{requestId})).status).toBe(409);
  });
  test('claim then failednativeguard retains failure and leaves mirror intact', async () => {
    const r = await repair(); const [command] = await claim(); expect(command.commandId).toBe(r.body.posDelivery.commandId);
    expect((await ack(command.commandId,'FAILED','table_busy')).status).toBe(201);
    const retried = await repair(); expect(retried.body.posDelivery.status).toBe('FAILED');
    expect(retried.body.posDelivery.code).toBe('table_busy'); expect(await db.edgeCommand.count()).toBe(1);
    expect((await db.table.findUniqueOrThrow({where:{id:tableId}})).activeOrderId).toBe(999);
  });
  test('verifiednativeACK atomicallyprojects mirror; terminalretry and repeatedACK are noops', async () => {
    await repair(); const [command] = await claim();
    expect((await ack(command.commandId)).status).toBe(201);
    let table = await db.table.findUniqueOrThrow({where:{id:tableId}});
    expect(table.isReserved).toBe(false); expect(table.activeOrderId).toBeNull(); expect(table.currentBill).toBe(0);
    await db.table.update({where:{id:tableId},data:{isReserved:true,activeOrderId:222,currentBill:12}});
    const retry = await repair(); expect(retry.body.success).toBe(true);
    expect(retry.body.posDelivery.status).toBe('SUCCEEDED');
    expect((await ack(command.commandId)).body.alreadyAcknowledged).toBe(true);
    table = await db.table.findUniqueOrThrow({where:{id:tableId}}); expect(table.activeOrderId).toBe(222);
  });
  test('delayedACK cannot overwrite a newer authoritative table projection', async () => {
    await repair(); const [command] = await claim();
    await db.table.update({where:{id:tableId},data:{activeOrderId:222,currentBill:12}});
    expect((await ack(command.commandId)).status).toBe(201);
    expect((await db.table.findUniqueOrThrow({where:{id:tableId}})).activeOrderId).toBe(222);
  });
  test('foreignDevice cannot acknowledge repair', async () => {
    await repair(); const [command] = await claim();
    expect((await ack(command.commandId,'SUCCEEDED','table_repaired',seeded.venues[1].credential)).status).toBe(404);
    expect((await db.edgeCommand.findUniqueOrThrow({where:{id:command.commandId}})).status).toBe('CLAIMED');
  });
  test('unclaimed repair cannot silentlymove to a replacement primary', async () => {
    const r = await repair();
    const replacement = await app.get(DeviceCredentialService).issueCredential({venueId:actor.venueId,installationId:randomUUID(),displayName:'Synthetic replacement',platform:'WINDOWS'});
    const replacementId = replacement.credential.split('.')[1];
    await db.venue.update({where:{id:actor.venueId},data:{activeOperationalDeviceId:replacementId}});
    const claimed = await post('/edge/commands/claim',{acceptedContractVersions:[2]},replacement.credential,true);
    expect(claimed.body.commands).toEqual([]);
    expect((await db.edgeCommand.findUniqueOrThrow({where:{id:r.body.posDelivery.commandId}})).deviceId).toBe(deviceId);
  });
  test('injectedenqueuefailure rollsback atomically without split mirror or pendingrow', async () => {
    const proxy = new Proxy(db,{get(target,property) {
      if (property==='$transaction') return (work:any)=>target.$transaction((tx)=>work(new Proxy(tx,{get(t,k){
        if(k==='edgeCommand') return new Proxy(t.edgeCommand,{get(e,j){if(j==='create')return ()=>{throw Error('Synthetic enqueue failure');};return Reflect.get(e,j);}});
        return Reflect.get(t,k);
      }})));
      const value=Reflect.get(target,property);return typeof value==='function'?value.bind(target):value;
    }});
    await expect(requestTableRepair(proxy,actor,'7','first',requestId)).rejects.toThrow('Synthetic enqueue failure');
    expect(await db.edgeCommand.count()).toBe(0);
    expect((await db.table.findUniqueOrThrow({where:{id:tableId}})).activeOrderId).toBe(999);
  });
  test('invalidsuccessresult cannotproject orcomplete the claimed command',async()=>{
    await repair();const [command]=await claim();expect((await ack(command.commandId,'SUCCEEDED','generic_success')).status).toBe(400);
    expect((await db.edgeCommand.findUniqueOrThrow({where:{id:command.commandId}})).status).toBe('CLAIMED');
    expect((await db.table.findUniqueOrThrow({where:{id:tableId}})).activeOrderId).toBe(999);
  });
  test('projection failure rolls back both ACK and Cloud mirror in one transaction', async () => {
    await repair(); const [command] = await claim();
    const proxy = new Proxy(db, {get(target, property) {
      if (property === '$transaction') return (work: any) => target.$transaction((tx) => work(new Proxy(tx, {get(t, k) {
        if (k === 'table') return new Proxy(t.table, {get(e, j) {
          if (j === 'updateMany') return () => { throw Error('Synthetic projection failure'); };
          const value = Reflect.get(e, j); return typeof value === 'function' ? value.bind(e) : value;
        }});
        const value = Reflect.get(t, k); return typeof value === 'function' ? value.bind(t) : value;
      }})));
      const value = Reflect.get(target, property); return typeof value === 'function' ? value.bind(target) : value;
    }});
    await expect(new EdgeCommandService(proxy).acknowledge(
      {venueId: actor.venueId, organizationId: actor.organizationId, deviceId},
      {commandId: command.commandId, status: 'SUCCEEDED', code: 'table_repaired'},
    )).rejects.toThrow('Synthetic projection failure');
    expect((await db.edgeCommand.findUniqueOrThrow({where: {id: command.commandId}})).status).toBe('CLAIMED');
    expect((await db.table.findUniqueOrThrow({where: {id: tableId}})).activeOrderId).toBe(999);
    expect((await ack(command.commandId)).status).toBe(201);
  });

});
