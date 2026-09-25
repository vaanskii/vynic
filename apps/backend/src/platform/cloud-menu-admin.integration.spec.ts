import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import { PlatformVenueConfigService } from './platform-venue-config.service';
const url = process.env.FOUNDATION_TEST_DATABASE_URL;
(url ? describe : describe.skip)('Cloud menu Admin (disposable PostgreSQL)', () => {
  let db: PrismaService, app: any, service: PlatformVenueConfigService, actor: any, venueId: string;
  beforeAll(async () => {
    const parsed = new URL(url!);
    if (!isFreshDisposableDatabase(parsed) && (parsed.hostname !== '127.0.0.1' || parsed.port !== '55439' || parsed.pathname !== '/vynic_foundation_phase3_disposable')) throw Error('Disposable foundation DB only');
    process.env.JWT_SECRET = 'foundation-test-signing-key';
    process.env.COOKIE_ENCRYPTION_KEY = 'foundation-test-cookie-key';
    db = new PrismaService({ datasourceUrl: url });
    app = await onboardingApp(db);
    service = app.get(PlatformVenueConfigService);
    const admin = await db.platformUser.create({ data: { email: `cloud-admin-${randomUUID()}@test.invalid`, displayName: 'Test admin', passwordHash: 'unused' } });
    actor = { platformUserId: admin.id, role: 'SUPER_ADMIN' };
    const venue = await db.venue.create({ data: { name: 'Unused test venue', timezone: 'Asia/Tbilisi', currency: 'GEL', organization: { create: { name: 'Disposable admin test' } } } });
    venueId = venue.id;
  });
  afterAll(async () => { await app?.close(); await db?.$disconnect(); });
  it('creates exactly a Website package idempotently without assigning a venue', async () => {
    await service.ensureWebsitePlan(actor);
    await service.ensureWebsitePlan(actor);
    const plans = await service.listPlans();
    expect(plans.filter(p => p.key === 'WEBSITE_ONLY')).toHaveLength(1);
    expect(plans.find(p => p.key === 'WEBSITE_ONLY')!.features.map(f => f.feature.key)).toEqual(['WEBSITE']);
    expect(await db.venuePlanAssignment.findUnique({ where: { venueId } })).toBeNull();
  });
  it('validates the boolean toggle and audits the transition once', async () => {
    await expect(service.enableCloudMenu(actor, venueId, 'yes')).rejects.toThrow('boolean');
    expect((await db.venue.findUniqueOrThrow({ where: { id: venueId } })).menuAuthority).toBe('POS');
    expect((await service.enableCloudMenu(actor, venueId, true)).menuManagement.authority).toBe('CLOUD');
    await service.enableCloudMenu(actor, venueId, true);
    expect(await db.platformAuditEvent.count({ where: { targetId: venueId, action: 'venue.cloud_menu_enabled' } })).toBe(1);
  });
  it('disables editing without transferring authority or deleting catalog, and reenables it', async () => {
    const category = await db.menuCategory.create({ data: { venueId, posMenuCategoryId: randomUUID(), nameKa: 'ტესტი', nameEn: 'Test', slug: randomUUID() } });
    const disabled = await service.enableCloudMenu(actor, venueId, false);
    expect(disabled.menuManagement).toMatchObject({ authority: 'CLOUD', enabled: false });
    expect(await db.menuCategory.findUnique({ where: { id: category.id } })).not.toBeNull();
    expect((await service.enableCloudMenu(actor, venueId, true)).menuManagement.enabled).toBe(true);
    await db.menuCategory.delete({ where: { id: category.id } });
  });
  it('rechecks stored operational history before writing', async () => {
    await db.venue.update({ where: { id: venueId }, data: { menuAuthority: 'POS' } });
    await db.setting.create({ data: { venueId, key: 'test-history', value: '{}' } });
    await expect(service.enableCloudMenu(actor, venueId, true)).rejects.toThrow('POS settings');
    expect((await db.venue.findUniqueOrThrow({ where: { id: venueId } })).menuAuthority).toBe('POS');
  });
});
