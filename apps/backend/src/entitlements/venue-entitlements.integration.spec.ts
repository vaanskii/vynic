jest.mock('../realtime/monitoring.gateway', () => ({
  MonitoringGateway: class {},
}));

import { FeatureOverrideEffect, WebsiteMode } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import {
  BOOTSTRAP_ORGANIZATION_ID,
  BOOTSTRAP_VENUE_ID,
} from '../auth/legacy-pos-tenant.service';
import type { TenantContext } from '../auth/pos-auth-context';
import { OrderSyncService } from '../pos/sync/snapshot/order-sync.service';
import { TableSyncService } from '../pos/sync/snapshot/table-sync.service';
import { FeatureKeys } from './feature-keys';
import { VenueEntitlementsService } from './venue-entitlements.service';

const { POS, WEBSITE, MANAGER_APP } = FeatureKeys;

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('Venue product entitlements (PostgreSQL)', () => {
  let prisma: PrismaService;
  let entitlements: VenueEntitlementsService;

  const suffix = `${process.pid}`.padStart(12, '0');
  const organizationId = `40000000-0000-4000-8000-${suffix}`;
  // A second Organization, to prove packages are not an Organization-wide fact.
  const otherOrganizationId = `41000000-0000-4000-8000-${suffix}`;
  const posOnly = `50000000-0000-4000-8000-${suffix}`;
  const posWebsite = `51000000-0000-4000-8000-${suffix}`;
  const posManager = `52000000-0000-4000-8000-${suffix}`;
  const full = `53000000-0000-4000-8000-${suffix}`;
  const unassigned = `54000000-0000-4000-8000-${suffix}`;
  const otherOrgVenue = `55000000-0000-4000-8000-${suffix}`;

  const venueIds = [
    posOnly,
    posWebsite,
    posManager,
    full,
    unassigned,
    otherOrgVenue,
  ];

  async function planId(key: string): Promise<string> {
    return (await prisma.plan.findUniqueOrThrow({ where: { key } })).id;
  }

  async function featureId(key: string): Promise<string> {
    return (await prisma.feature.findUniqueOrThrow({ where: { key } })).id;
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();
    entitlements = new VenueEntitlementsService(prisma);

    const venue = (id: string, name: string) => ({
      id,
      name,
      timezone: 'Asia/Tbilisi',
      currency: 'GEL',
    });

    await prisma.organization.create({
      data: {
        id: organizationId,
        name: 'Entitlement fixture',
        venues: {
          create: [
            venue(posOnly, 'POS only'),
            venue(posWebsite, 'POS and website'),
            venue(posManager, 'POS and manager'),
            venue(full, 'Full package'),
            venue(unassigned, 'Unassigned'),
          ],
        },
      },
    });
    await prisma.organization.create({
      data: {
        id: otherOrganizationId,
        name: 'Second organization fixture',
        venues: { create: [venue(otherOrgVenue, 'Other organization venue')] },
      },
    });

    await prisma.venuePlanAssignment.createMany({
      data: [
        { venueId: posOnly, planId: await planId('POS') },
        { venueId: posWebsite, planId: await planId('POS_WEBSITE') },
        { venueId: posManager, planId: await planId('POS_MANAGER') },
        { venueId: full, planId: await planId('POS_WEBSITE_MANAGER') },
        { venueId: otherOrgVenue, planId: await planId('POS') },
      ],
    });

    await prisma.venueWebsiteConfig.createMany({
      data: [
        { venueId: posWebsite, mode: WebsiteMode.SAAS },
        { venueId: full, mode: WebsiteMode.CUSTOM },
      ],
    });
  });

  afterAll(async () => {
    await prisma.venueFeatureOverride.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venueWebsiteConfig.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venuePlanAssignment.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.order.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.table.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.deleteMany({
      where: { id: { in: [organizationId, otherOrganizationId] } },
    });
    await prisma.$disconnect();
  });

  it('represents every package the business sells', async () => {
    await expect(entitlements.effectiveFeatures(posOnly)).resolves.toEqual([
      POS,
    ]);
    await expect(entitlements.effectiveFeatures(posWebsite)).resolves.toEqual([
      POS,
      WEBSITE,
    ]);
    await expect(entitlements.effectiveFeatures(posManager)).resolves.toEqual([
      MANAGER_APP,
      POS,
    ]);
    await expect(entitlements.effectiveFeatures(full)).resolves.toEqual([
      MANAGER_APP,
      POS,
      WEBSITE,
    ]);
  });

  it('entitles a Venue with no plan assignment to nothing', async () => {
    await expect(entitlements.effectiveFeatures(unassigned)).resolves.toEqual(
      [],
    );
  });

  it('resolves two Venues on the same plan independently', async () => {
    const [a, b] = await Promise.all([
      entitlements.effectiveFeatures(posOnly),
      entitlements.effectiveFeatures(otherOrgVenue),
    ]);

    expect(a).toEqual([POS]);
    expect(b).toEqual([POS]);

    await prisma.venueFeatureOverride.create({
      data: {
        venueId: otherOrgVenue,
        featureId: await featureId(WEBSITE),
        effect: FeatureOverrideEffect.ENABLED,
        note: 'Same plan, different Venue — must not leak.',
      },
    });

    await expect(
      entitlements.effectiveFeatures(otherOrgVenue),
    ).resolves.toEqual([POS, WEBSITE]);
    await expect(entitlements.effectiveFeatures(posOnly)).resolves.toEqual([
      POS,
    ]);
  });

  it('lets one Organization own Venues with different packages', async () => {
    const packages = await Promise.all(
      [posOnly, posWebsite, posManager, full].map((id) =>
        entitlements.effectiveFeatures(id),
      ),
    );

    expect(packages).toEqual([
      [POS],
      [POS, WEBSITE],
      [MANAGER_APP, POS],
      [MANAGER_APP, POS, WEBSITE],
    ]);
    expect(
      await prisma.venue.count({ where: { organizationId } }),
    ).toBeGreaterThan(1);
  });

  it('grants a feature the plan lacks through an ENABLED override', async () => {
    await prisma.venueFeatureOverride.create({
      data: {
        venueId: posOnly,
        featureId: await featureId(MANAGER_APP),
        effect: FeatureOverrideEffect.ENABLED,
        note: 'Beta access without a new plan.',
      },
    });

    await expect(entitlements.effectiveFeatures(posOnly)).resolves.toEqual([
      MANAGER_APP,
      POS,
    ]);
  });

  it('withholds a feature the plan includes through a DISABLED override', async () => {
    await prisma.venueFeatureOverride.create({
      data: {
        venueId: full,
        featureId: await featureId(WEBSITE),
        effect: FeatureOverrideEffect.DISABLED,
        note: 'Website suspended by agreement.',
      },
    });

    await expect(entitlements.effectiveFeatures(full)).resolves.toEqual([
      MANAGER_APP,
      POS,
    ]);

    // The stored CUSTOM mode survives the entitlement being withdrawn.
    await expect(entitlements.websiteAccess(full)).resolves.toEqual({
      entitled: false,
      configuredMode: WebsiteMode.CUSTOM,
      effectiveMode: WebsiteMode.NONE,
      consistent: false,
    });
  });

  it('keeps website entitlement and website mode as separate facts', async () => {
    await expect(entitlements.websiteAccess(posWebsite)).resolves.toEqual({
      entitled: true,
      configuredMode: WebsiteMode.SAAS,
      effectiveMode: WebsiteMode.SAAS,
      consistent: true,
    });
    // Entitled to no website, and configured with none — a different state
    // from "entitled but not configured".
    await expect(entitlements.websiteAccess(posOnly)).resolves.toEqual({
      entitled: false,
      configuredMode: WebsiteMode.NONE,
      effectiveMode: WebsiteMode.NONE,
      consistent: true,
    });
    await expect(entitlements.websiteAccess(posManager)).resolves.toMatchObject(
      { entitled: false, configuredMode: WebsiteMode.NONE },
    );
  });

  it('enforces one plan assignment and one override row per Venue feature', async () => {
    await expect(
      prisma.venuePlanAssignment.create({
        data: { venueId: posOnly, planId: await planId('POS_WEBSITE') },
      }),
    ).rejects.toMatchObject({ code: 'P2002' });

    await expect(
      prisma.venueFeatureOverride.create({
        data: {
          venueId: posOnly,
          featureId: await featureId(MANAGER_APP),
          effect: FeatureOverrideEffect.DISABLED,
        },
      }),
    ).rejects.toMatchObject({ code: 'P2002' });
  });

  it('refuses a plan assignment or override for a Venue that does not exist', async () => {
    await expect(
      prisma.venuePlanAssignment.create({
        data: {
          venueId: '99999999-0000-4000-8000-000000000000',
          planId: await planId('POS'),
        },
      }),
    ).rejects.toMatchObject({ code: 'P2003' });
  });

  it('keeps POS sync working for a Venue entitled to neither Manager nor Website', async () => {
    // The invariant: commercial packaging sits above synchronization. A
    // POS-only customer must still mirror operational data to Cloud, or their
    // history would not be there when they buy Manager later.
    await expect(
      entitlements.effectiveFeatures(posManager),
    ).resolves.not.toContain(WEBSITE);
    const tenant: TenantContext = {
      venueId: posOnly,
      organizationId,
    };
    expect(await entitlements.hasFeature(posOnly, MANAGER_APP)).toBe(true);

    await prisma.venueFeatureOverride.update({
      where: {
        venueId_featureId: {
          venueId: posOnly,
          featureId: await featureId(MANAGER_APP),
        },
      },
      data: { effect: FeatureOverrideEffect.DISABLED },
    });
    expect(await entitlements.hasFeature(posOnly, MANAGER_APP)).toBe(false);
    expect(await entitlements.hasFeature(posOnly, WEBSITE)).toBe(false);

    await new TableSyncService(prisma).sync(
      tenant,
      [
        {
          tableNumber: '4',
          floor: 'first',
          isReserved: false,
          activeOrderId: 401,
          currentBill: 42,
        },
      ],
      false,
    );
    await new OrderSyncService(prisma).sync(
      tenant,
      [
        {
          posOrderId: 401,
          status: 'open',
          totalAmount: 42,
          waiterName: 'admin',
          floor: 'first',
          businessDate: '2026-08-31',
          tableNumbers: ['4'],
          items: [],
        },
      ],
      '2026-08-31',
    );

    expect(await prisma.table.count({ where: { venueId: posOnly } })).toBe(1);
    expect(
      await prisma.order.findFirstOrThrow({
        where: { venueId: posOnly, posOrderId: 401 },
      }),
    ).toMatchObject({ status: 'open', totalAmount: 42 });
  });

  it('leaves the bootstrap Vankisi Venue with everything it could already do', async () => {
    await expect(
      entitlements.effectiveFeatures(BOOTSTRAP_VENUE_ID),
    ).resolves.toEqual([MANAGER_APP, POS, WEBSITE]);

    await expect(
      entitlements.websiteAccess(BOOTSTRAP_VENUE_ID),
    ).resolves.toEqual({
      entitled: true,
      configuredMode: WebsiteMode.CUSTOM,
      effectiveMode: WebsiteMode.CUSTOM,
      consistent: true,
    });

    expect(
      await prisma.venue.findUniqueOrThrow({
        where: { id: BOOTSTRAP_VENUE_ID },
        select: { organizationId: true },
      }),
    ).toEqual({ organizationId: BOOTSTRAP_ORGANIZATION_ID });
  });
});
