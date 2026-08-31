process.env.JWT_SECRET ??= 'platform-control-plane-integration-secret';

import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import {
  DeviceStatus,
  FeatureOverrideEffect,
  PlatformUserStatus,
  VenueDomainStatus,
  VenueStatus,
  WebsiteMode,
} from '@prisma/client';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { DeviceCredentialService } from '../auth/device-credential.service';
import { EdgeCommandService } from '../edge/edge-command.service';
import { FeatureKeys } from '../entitlements/feature-keys';
import { FeatureGuard } from '../entitlements/feature.guard';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { WebsiteTenantService } from '../website/tenancy/website-tenant.service';
import { PlatformAuditService } from './platform-audit.service';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformAuthService } from './platform-auth.service';
import { PlatformDeviceService } from './platform-device.service';
import { PlatformDirectoryService } from './platform-directory.service';
import { PlatformOrganizationsController } from './platform-organizations.controller';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import { PlatformVenuesController } from './platform-venues.controller';
import type { PlatformPrincipal } from './platform-auth-context';

const databaseUrl = process.env.TENANT_INTEGRATION_DATABASE_URL;
const describeDatabase = databaseUrl ? describe : describe.skip;

describeDatabase('Platform control plane (PostgreSQL)', () => {
  let prisma: PrismaService;
  let jwt: JwtService;
  let auth: PlatformAuthService;
  let guard: PlatformAuthGuard;
  let audit: PlatformAuditService;
  let directory: PlatformDirectoryService;
  let config: PlatformVenueConfigService;
  let devices: PlatformDeviceService;
  let entitlements: VenueEntitlementsService;
  let credentials: DeviceCredentialService;
  let edgeCommands: EdgeCommandService;
  let websiteTenant: WebsiteTenantService;
  let organizations: PlatformOrganizationsController;
  let venues: PlatformVenuesController;

  const suffix = `${process.pid}`.padStart(12, '0');
  const adminEmail = `admin-${suffix}@vynic.test`;
  const disabledEmail = `retired-${suffix}@vynic.test`;
  const password = 'a-long-enough-test-password';

  const hostA = `a-${suffix}.test`;
  const hostB = `b-${suffix}.test`;

  let actor: PlatformPrincipal;
  let adminId: string;
  let disabledAdminId: string;
  let organizationAId: string;
  let organizationBId: string;
  let venueAId: string;
  let venueBId: string;

  const created = { organizations: [] as string[], venues: [] as string[] };

  function contextFor(headers: Record<string, string | undefined>) {
    const request: Record<string, unknown> = { headers };
    return {
      request,
      context: {
        switchToHttp: () => ({ getRequest: () => request }),
      } as never,
    };
  }

  async function planId(key: string) {
    return (await prisma.plan.findUniqueOrThrow({ where: { key } })).id;
  }

  beforeAll(async () => {
    prisma = new PrismaService({ datasourceUrl: databaseUrl });
    await prisma.$connect();

    jwt = new JwtService({ secret: process.env.JWT_SECRET });
    const configService = {
      get: (key: string) => process.env[key],
    } as unknown as ConfigService;

    auth = new PlatformAuthService(prisma, jwt, configService);
    guard = new PlatformAuthGuard(auth);
    audit = new PlatformAuditService(prisma);
    entitlements = new VenueEntitlementsService(prisma);
    credentials = new DeviceCredentialService(prisma);
    edgeCommands = new EdgeCommandService(prisma);
    websiteTenant = new WebsiteTenantService(prisma, {
      get: (key: string) => (key === 'NODE_ENV' ? 'production' : undefined),
    } as never);

    directory = new PlatformDirectoryService(prisma, audit);
    config = new PlatformVenueConfigService(
      prisma,
      entitlements,
      directory,
      audit,
    );
    devices = new PlatformDeviceService(
      prisma,
      credentials,
      edgeCommands,
      directory,
      audit,
    );
    organizations = new PlatformOrganizationsController(directory);
    venues = new PlatformVenuesController(directory, config, devices);

    const passwordHash = await argon2.hash(password, {
      type: argon2.argon2id,
    });
    const admin = await prisma.platformUser.create({
      data: { email: adminEmail, displayName: 'Test Admin', passwordHash },
      select: { id: true, email: true, displayName: true, role: true },
    });
    adminId = admin.id;
    actor = {
      platformUserId: admin.id,
      email: admin.email,
      displayName: admin.displayName,
      role: admin.role,
    };

    const disabled = await prisma.platformUser.create({
      data: {
        email: disabledEmail,
        displayName: 'Retired Admin',
        passwordHash,
        status: PlatformUserStatus.DISABLED,
      },
      select: { id: true },
    });
    disabledAdminId = disabled.id;
  });

  afterAll(async () => {
    const venueIds = created.venues;
    await prisma.edgeCommand.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.device.deleteMany({ where: { venueId: { in: venueIds } } });
    await prisma.venueDomain.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venueFeatureOverride.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venueWebsiteConfig.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venuePlanAssignment.deleteMany({
      where: { venueId: { in: venueIds } },
    });
    await prisma.venue.deleteMany({ where: { id: { in: venueIds } } });
    await prisma.organization.deleteMany({
      where: { id: { in: created.organizations } },
    });
    await prisma.platformAuditEvent.deleteMany({
      where: { platformUserId: { in: [adminId, disabledAdminId] } },
    });
    await prisma.platformUser.deleteMany({
      where: { id: { in: [adminId, disabledAdminId] } },
    });
    await prisma.$disconnect();
  });

  describe('authentication', () => {
    it('accepts the right password and reports the principal', async () => {
      const result = await auth.login(adminEmail.toUpperCase(), password);

      expect(result.actor).toMatchObject({
        platformUserId: adminId,
        email: adminEmail,
        role: 'SUPER_ADMIN',
      });
      expect(result.access_token).toEqual(expect.any(String));
      // No venue, no organization: a platform administrator is above tenants.
      expect(result.actor).not.toHaveProperty('venueId');
      expect(result.actor).not.toHaveProperty('organizationId');
    });

    it('answers a wrong password and an unknown address identically', async () => {
      // Otherwise the response enumerates which administrators exist.
      await expect(auth.login(adminEmail, 'wrong-password')).rejects.toThrow(
        'Invalid credentials',
      );
      await expect(
        auth.login(`nobody-${suffix}@vynic.test`, password),
      ).rejects.toThrow('Invalid credentials');
    });

    it('refuses a disabled administrator before checking the password', async () => {
      await expect(auth.login(disabledEmail, password)).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
    });

    it('records the sign-in time', async () => {
      await auth.login(adminEmail, password);
      const user = await prisma.platformUser.findUniqueOrThrow({
        where: { id: adminId },
        select: { lastLoginAt: true },
      });
      expect(user.lastLoginAt).not.toBeNull();
    });
  });

  describe('token isolation', () => {
    it('admits a platform token', async () => {
      const { access_token } = await auth.login(adminEmail, password);
      const { request, context } = contextFor({
        authorization: `Bearer ${access_token}`,
      });

      await expect(guard.canActivate(context)).resolves.toBe(true);
      expect(request.platformPrincipal).toMatchObject({
        platformUserId: adminId,
      });
    });

    it('refuses a manager token signed with the same secret', async () => {
      // The manager token is a valid JWT under JWT_SECRET. It carries no
      // platform audience and no principal type, and its subject is a Staff id.
      const managerToken = jwt.sign({
        sub: adminId,
        username: 'admin',
        role: 'MANAGER',
      });

      await expect(
        guard.canActivate(
          contextFor({ authorization: `Bearer ${managerToken}` }).context,
        ),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('refuses a website customer token', async () => {
      const websiteToken = jwt.sign({
        sub: adminId,
        phone: '+995500000000',
        role: 'USER',
      });

      await expect(
        guard.canActivate(
          contextFor({ authorization: `Bearer ${websiteToken}` }).context,
        ),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('refuses a token that claims the platform type but not the audience', async () => {
      const forged = jwt.sign({ sub: adminId, typ: 'PLATFORM' });

      await expect(
        guard.canActivate(
          contextFor({ authorization: `Bearer ${forged}` }).context,
        ),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('refuses a device credential, which is not a bearer token at all', async () => {
      await expect(
        guard.canActivate(
          contextFor({ authorization: 'Bearer vynic-device-v1.x.y' }).context,
        ),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    });

    it('refuses a missing or malformed header', async () => {
      for (const header of [undefined, '', 'Basic abc', 'Bearer ']) {
        await expect(
          guard.canActivate(contextFor({ authorization: header }).context),
        ).rejects.toBeInstanceOf(UnauthorizedException);
      }
    });

    it('stops admitting an administrator the moment they are disabled', async () => {
      const { access_token } = await auth.login(adminEmail, password);
      await prisma.platformUser.update({
        where: { id: adminId },
        data: { status: PlatformUserStatus.DISABLED },
      });

      // The token is still signed and unexpired; the principal is re-read.
      await expect(
        guard.canActivate(
          contextFor({ authorization: `Bearer ${access_token}` }).context,
        ),
      ).rejects.toBeInstanceOf(UnauthorizedException);

      await prisma.platformUser.update({
        where: { id: adminId },
        data: { status: PlatformUserStatus.ACTIVE },
      });
    });
  });

  describe('organizations and venues', () => {
    it('creates two organizations and sees both', async () => {
      const a = await organizations.create(actor, {
        name: `Org A ${suffix}`,
      });
      const b = await organizations.create(actor, {
        name: `Org B ${suffix}`,
      });
      organizationAId = a.id;
      organizationBId = b.id;
      created.organizations.push(a.id, b.id);

      const listed = await organizations.list({ limit: '200' });
      const ids = listed.items.map((item) => item.id);
      expect(ids).toEqual(expect.arrayContaining([a.id, b.id]));
      expect(listed.limit).toBe(200);
    });

    it('creates a venue under each organization and nothing else', async () => {
      const a = await venues.create(actor, {
        organizationId: organizationAId,
        name: 'Venue A',
        timezone: 'Asia/Tbilisi',
        currency: 'GEL',
      });
      const b = await venues.create(actor, {
        organizationId: organizationBId,
        name: 'Venue B',
        timezone: 'Europe/Berlin',
        currency: 'EUR',
      });
      venueAId = a.id;
      venueBId = b.id;
      created.venues.push(a.id, b.id);

      expect(a.organizationId).toBe(organizationAId);
      expect(b.organizationId).toBe(organizationBId);
      // No fabricated data in a real restaurant's account on day one.
      expect(await prisma.table.count({ where: { venueId: a.id } })).toBe(0);
      expect(await prisma.menuItem.count({ where: { venueId: a.id } })).toBe(0);
      expect(await prisma.device.count({ where: { venueId: a.id } })).toBe(0);
      expect(await prisma.venueDomain.count({ where: { venueId: a.id } })).toBe(
        0,
      );
      expect(
        await prisma.venuePlanAssignment.count({ where: { venueId: a.id } }),
      ).toBe(0);
    });

    it('never reuses the deterministic bootstrap ids', () => {
      // Those belong to the existing Vankisi installation and must never be
      // handed to a second customer.
      expect(venueAId).not.toBe('00000000-0000-4000-8000-000000000002');
      expect(organizationAId).not.toBe('00000000-0000-4000-8000-000000000001');
    });

    it('filters venues by organization without crossing them', async () => {
      const forA = await venues.list({
        limit: '200',
        organizationId: organizationAId,
      });
      expect(forA.items.map((item) => item.id)).toEqual([venueAId]);
    });

    it('updates metadata and toggles status', async () => {
      await venues.update(actor, venueAId, { name: 'Venue A renamed' });
      expect((await venues.read(venueAId)).name).toBe('Venue A renamed');

      await venues.setStatus(actor, venueAId, {
        status: VenueStatus.DISABLED,
      });
      expect((await venues.read(venueAId)).status).toBe(VenueStatus.DISABLED);

      await venues.setStatus(actor, venueAId, { status: VenueStatus.ACTIVE });
      expect((await venues.read(venueAId)).status).toBe(VenueStatus.ACTIVE);
    });

    it('rejects a malformed identifier before it reaches the database', async () => {
      await expect(venues.read('not-a-uuid')).rejects.toBeInstanceOf(
        BadRequestException,
      );
      await expect(
        venues.create(actor, {
          organizationId: organizationAId,
          name: '',
          timezone: 'UTC',
          currency: 'GEL',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      await expect(
        venues.create(actor, {
          organizationId: organizationAId,
          name: 'X',
          timezone: 'UTC',
          currency: 'GELL',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('reports an unknown venue as missing', async () => {
      await expect(
        venues.read('99999999-9999-4999-8999-999999999999'),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('plans and feature overrides', () => {
    it('assigns different plans to the two venues', async () => {
      await venues.assignPlan(actor, venueAId, {
        planId: await planId('POS_WEBSITE_MANAGER'),
      });
      await venues.assignPlan(actor, venueBId, { planId: await planId('POS') });

      const productA = await venues.readProduct(venueAId);
      const productB = await venues.readProduct(venueBId);

      expect(productA.plan?.key).toBe('POS_WEBSITE_MANAGER');
      expect(productB.plan?.key).toBe('POS');
      expect(productA.effectiveFeatures).toEqual(
        expect.arrayContaining([
          FeatureKeys.POS,
          FeatureKeys.WEBSITE,
          FeatureKeys.MANAGER_APP,
        ]),
      );
      expect(productB.effectiveFeatures).toEqual([FeatureKeys.POS]);
    });

    it('an override changes what the production guard enforces', async () => {
      // The point of the whole phase: a control-plane mutation and the runtime
      // check must agree, because they read the same resolver.
      const featureGuard = (venueId: string) =>
        new FeatureGuard(
          { getAllAndOverride: () => FeatureKeys.MANAGER_APP } as never,
          entitlements,
        ).canActivate({
          getHandler: () => () => undefined,
          getClass: () => class {},
          switchToHttp: () => ({
            getRequest: () => ({
              user: { venueId, organizationId: organizationBId },
            }),
          }),
        } as never);

      await expect(featureGuard(venueBId)).rejects.toBeInstanceOf(
        ForbiddenException,
      );

      await venues.setFeatureOverride(actor, venueBId, 'manager_app', {
        effect: FeatureOverrideEffect.ENABLED,
        note: 'Trial',
      });

      await expect(
        entitlements.hasFeature(venueBId, FeatureKeys.MANAGER_APP),
      ).resolves.toBe(true);
      await expect(featureGuard(venueBId)).resolves.toBe(true);
    });

    it('removing the override goes back to what the plan says', async () => {
      const product = await venues.clearFeatureOverride(
        actor,
        venueBId,
        FeatureKeys.MANAGER_APP,
      );

      expect(product.overrides).toEqual([]);
      expect(product.effectiveFeatures).toEqual([FeatureKeys.POS]);
    });

    it('a disabling override wins over the plan', async () => {
      await venues.setFeatureOverride(actor, venueAId, FeatureKeys.WEBSITE, {
        effect: FeatureOverrideEffect.DISABLED,
      });
      await expect(
        entitlements.hasFeature(venueAId, FeatureKeys.WEBSITE),
      ).resolves.toBe(false);

      await venues.clearFeatureOverride(actor, venueAId, FeatureKeys.WEBSITE);
      await expect(
        entitlements.hasFeature(venueAId, FeatureKeys.WEBSITE),
      ).resolves.toBe(true);
    });

    it('refuses an unknown feature key', async () => {
      await expect(
        venues.setFeatureOverride(actor, venueAId, 'NOT_A_FEATURE', {
          effect: FeatureOverrideEffect.ENABLED,
        }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('website mode and domains', () => {
    it('configures a different mode per venue', async () => {
      const a = await venues.setWebsiteMode(actor, venueAId, {
        mode: WebsiteMode.CUSTOM,
      });
      const b = await venues.setWebsiteMode(actor, venueBId, {
        mode: WebsiteMode.NONE,
      });

      expect(a).toMatchObject({
        entitled: true,
        configuredMode: WebsiteMode.CUSTOM,
        effectiveMode: WebsiteMode.CUSTOM,
        consistent: true,
      });
      expect(b.effectiveMode).toBe(WebsiteMode.NONE);
    });

    it('reports an inconsistent configuration instead of rewriting it', async () => {
      // Venue B has no WEBSITE. Setting SAAS is allowed and reported as
      // inconsistent — the administrator is told what they have, not corrected.
      const result = await venues.setWebsiteMode(actor, venueBId, {
        mode: WebsiteMode.SAAS,
      });

      expect(result).toMatchObject({
        entitled: false,
        configuredMode: WebsiteMode.SAAS,
        effectiveMode: WebsiteMode.NONE,
        consistent: false,
      });
      await venues.setWebsiteMode(actor, venueBId, { mode: WebsiteMode.NONE });
    });

    it('a registered hostname resolves through the real public resolver', async () => {
      const domain = await venues.registerDomain(actor, venueAId, {
        hostname: `  ${hostA.toUpperCase()}:443 `,
      });

      // Normalized by the same function the public request path uses.
      expect(domain.hostname).toBe(hostA);
      await expect(
        websiteTenant.resolveRequest({ headers: { host: hostA } }),
      ).resolves.toMatchObject({
        tenant: { venueId: venueAId, organizationId: organizationAId },
        configuredMode: WebsiteMode.CUSTOM,
      });
    });

    it('keeps each venue hostname to itself', async () => {
      await venues.registerDomain(actor, venueBId, { hostname: hostB });

      await expect(
        websiteTenant.resolveByHostname(hostB),
      ).resolves.toMatchObject({ tenant: { venueId: venueBId } });
      expect(
        (await venues.listDomains(venueAId)).map((d) => d.hostname),
      ).toEqual([hostA]);
    });

    it('refuses to point one hostname at two venues', async () => {
      await expect(
        venues.registerDomain(actor, venueBId, { hostname: hostA }),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('refuses a value that is not a hostname', async () => {
      await expect(
        venues.registerDomain(actor, venueAId, {
          hostname: 'https://a.test/menu',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('disabling a domain stops it serving without releasing the name', async () => {
      const [domain] = await venues.listDomains(venueAId);
      await venues.setDomainStatus(actor, venueAId, domain.id, {
        status: VenueDomainStatus.DISABLED,
      });

      await expect(websiteTenant.resolveByHostname(hostA)).resolves.toBeNull();
      // Still reserved: nobody else can take it.
      await expect(
        venues.registerDomain(actor, venueBId, { hostname: hostA }),
      ).rejects.toBeInstanceOf(ConflictException);

      await venues.setDomainStatus(actor, venueAId, domain.id, {
        status: VenueDomainStatus.ACTIVE,
      });
      await expect(
        websiteTenant.resolveByHostname(hostA),
      ).resolves.not.toBeNull();
    });

    it('will not touch another venue domain', async () => {
      const [domainB] = await venues.listDomains(venueBId);
      await expect(
        venues.setDomainStatus(actor, venueAId, domainB.id, {
          status: VenueDomainStatus.DISABLED,
        }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('releasing a hostname frees it for another venue', async () => {
      const [domainB] = await venues.listDomains(venueBId);
      await venues.releaseDomain(actor, venueBId, domainB.id);

      await expect(websiteTenant.resolveByHostname(hostB)).resolves.toBeNull();
      const moved = await venues.registerDomain(actor, venueAId, {
        hostname: hostB,
      });
      expect(moved.venueId).toBe(venueAId);
      await venues.releaseDomain(actor, venueAId, moved.id);
    });
  });

  describe('devices', () => {
    let deviceAId: string;
    let deviceBId: string;
    let credentialA: string;
    let credentialB: string;

    it('issues a credential exactly once per device', async () => {
      const a = await venues.createDevice(actor, venueAId, {
        displayName: 'Venue A bar terminal',
        platform: 'windows',
      });
      const b = await venues.createDevice(actor, venueBId, {
        displayName: 'Venue B terminal',
        platform: 'windows',
      });
      deviceAId = a.device.id;
      deviceBId = b.device.id;
      credentialA = a.credential;
      credentialB = b.credential;

      expect(credentialA).toMatch(/^vynic-device-v1\./);
      expect(credentialA).not.toBe(credentialB);
    });

    it('authenticates each device into its own venue', async () => {
      await expect(
        credentials.verifyCredential(credentialA),
      ).resolves.toMatchObject({
        deviceId: deviceAId,
        venueId: venueAId,
        organizationId: organizationAId,
      });
      await expect(
        credentials.verifyCredential(credentialB),
      ).resolves.toMatchObject({ venueId: venueBId });
    });

    it('never returns the secret or its hash on a read', async () => {
      const device = await venues.readDevice(venueAId, deviceAId);
      const listed = await venues.listDevices(venueAId);

      for (const row of [device, ...listed]) {
        expect(row).not.toHaveProperty('credentialHash');
        expect(row).not.toHaveProperty('credential');
      }
      expect(device).toMatchObject({
        installationId: expect.any(String) as unknown,
        platform: 'windows',
        status: DeviceStatus.ACTIVE,
      });
      expect(JSON.stringify(listed)).not.toContain('$argon2');
    });

    it('will not read another venue device', async () => {
      await expect(
        venues.readDevice(venueAId, deviceBId),
      ).rejects.toBeInstanceOf(NotFoundException);
    });

    it('rotation replaces the secret and kills the old one immediately', async () => {
      const rotated = await venues.rotateCredential(actor, venueAId, deviceAId);

      expect(rotated.credential).not.toBe(credentialA);
      expect(rotated.device.id).toBe(deviceAId);
      await expect(
        credentials.verifyCredential(credentialA),
      ).resolves.toBeNull();
      await expect(
        credentials.verifyCredential(rotated.credential),
      ).resolves.toMatchObject({ venueId: venueAId });
      credentialA = rotated.credential;
    });

    it('revoking a device stops its credential working', async () => {
      await venues.setDeviceStatus(actor, venueAId, deviceAId, {
        status: DeviceStatus.REVOKED,
      });

      await expect(
        credentials.verifyCredential(credentialA),
      ).resolves.toBeNull();

      await venues.setDeviceStatus(actor, venueAId, deviceAId, {
        status: DeviceStatus.ACTIVE,
      });
      await expect(
        credentials.verifyCredential(credentialA),
      ).resolves.not.toBeNull();
    });

    it('queues a NOOP that only the addressed device can claim', async () => {
      const queued = await venues.enqueueTestCommand(actor, venueAId, {
        deviceId: deviceAId,
      });

      expect(queued.status).toBe('PENDING');
      const stored = await prisma.edgeCommand.findUniqueOrThrow({
        where: { id: queued.commandId },
        select: { venueId: true, deviceId: true, type: true },
      });
      expect(stored).toEqual({
        venueId: venueAId,
        deviceId: deviceAId,
        type: 'NOOP',
      });

      const claimedByB = await edgeCommands.claim({
        deviceId: deviceBId,
        venueId: venueBId,
        organizationId: organizationBId,
      });
      expect(claimedByB).toEqual([]);

      const claimedByA = await edgeCommands.claim({
        deviceId: deviceAId,
        venueId: venueAId,
        organizationId: organizationAId,
      });
      expect(claimedByA.map((c) => c.commandId)).toEqual([queued.commandId]);
    });

    it('will not queue work for another venue device', async () => {
      await expect(
        venues.enqueueTestCommand(actor, venueAId, { deviceId: deviceBId }),
      ).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  describe('audit trail', () => {
    it('records who changed what, and never a secret', async () => {
      const events = await audit.recent(200, 0);
      const actions = events.map((event) => event.action);

      expect(actions).toEqual(
        expect.arrayContaining([
          'organization.created',
          'venue.created',
          'venue.status_changed',
          'venue.plan_assigned',
          'venue.feature_override_set',
          'venue.feature_override_removed',
          'venue.website_mode_changed',
          'venue.domain_registered',
          'venue.domain_status_changed',
          'venue.domain_released',
          'device.created',
          'device.credential_issued',
          'device.status_changed',
          'device.edge_test_command_enqueued',
        ]),
      );
      for (const event of events) {
        expect(event.actor.id).toBe(adminId);
      }

      const serialized = JSON.stringify(events);
      expect(serialized).not.toContain('vynic-device-v1.');
      expect(serialized).not.toContain('$argon2');
      expect(serialized).not.toContain(password);
    });

    it('is not written into the restaurant operational audit log', async () => {
      // A platform action recorded there would claim an employee did it.
      expect(
        await prisma.auditEventLog.count({
          where: { venueId: { in: [venueAId, venueBId] } },
        }),
      ).toBe(0);
    });
  });
});
