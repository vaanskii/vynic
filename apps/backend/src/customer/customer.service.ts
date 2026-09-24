import { requireCommercialFeature } from '../entitlements/commercial-state';
import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma.service';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { PlatformCommercialService } from '../platform/platform-commercial.service';
import { DeviceEnrollmentService } from '../edge/device-enrollment.service';
import { requireText } from '../platform/platform-validation';
import type { CustomerPrincipal } from './customer-auth';
import type { ControlActor } from '../platform/control-actor';
import { profileInput, saveProfile } from '../venue-profile/venue-profile';
import { initializeWebsite } from './onboarding-website';
import { Prisma } from '@prisma/client';

@Injectable()
export class CustomerService {
  constructor(
    private readonly db: PrismaService,
    private readonly entitlements: VenueEntitlementsService,
    private readonly commercial: PlatformCommercialService,
    private readonly enrollments: DeviceEnrollmentService,
    @Optional() private readonly config?: ConfigService,
  ) {}
  async requireFeature(id: string, feature: string) {
    return requireCommercialFeature(this.db, id, feature);
  }
  async venue(actor: CustomerPrincipal, id: string) {
    const venue = await this.db.venue.findFirst({
      where: {
        id,
        organization: {
          memberships: {
            some: { customerAccountId: actor.customerAccountId, role: 'OWNER' },
          },
        },
      },
    });
    if (!venue) throw new NotFoundException('Restaurant not found');
    return venue;
  }
  async profile(
    actor: CustomerPrincipal,
    id: string,
    body: Record<string, unknown>,
  ) {
    await this.venue(actor, id);
    return saveProfile(this.db, id, body, {
      id: actor.customerAccountId,
      source: 'CUSTOMER',
    });
  }
  async portal(actor: CustomerPrincipal) {
    const account = await this.db.customerAccount.findUniqueOrThrow({
      where: { id: actor.customerAccountId },
      select: { email: true, displayName: true, emailVerifiedAt: true },
    });
    const venues = await this.db.venue.findMany({
      where: {
        organization: {
          memberships: {
            some: { customerAccountId: actor.customerAccountId, role: 'OWNER' },
          },
        },
      },
      select: { id: true },
    });
    const policy = await this.db.onboardingPolicy.findUnique({
      where: { id: 'default' },
    });
    const statuses = await Promise.all(venues.map((v) => this.status(v.id)));
    const enabled = new Set(statuses.flatMap((v) => v.features));
    return {
      account,
      organizations: await this.db.organization.findMany({
        where: {
          memberships: {
            some: { customerAccountId: actor.customerAccountId, role: 'OWNER' },
          },
        },
        select: { id: true, name: true },
        orderBy: { createdAt: 'asc' },
      }),
      venues: statuses,
      releaseLinks: Object.fromEntries(
        Object.entries(
          (policy?.releaseLinks ?? {}) as Record<string, string>,
        ).filter(([key]) =>
          enabled.has(key.startsWith('pos') ? 'POS' : 'MANAGER_APP'),
        ),
      ),
      // Lets first-run show the full website address before a Venue exists.
      websiteBaseDomain:
        this.config?.get<string>('SAAS_WEBSITE_BASE_DOMAIN') ?? null,
    };
  }
  async status(id: string) {
    const features = await this.entitlements.effectiveFeatures(id);
    const venue = await this.db.venue.findUniqueOrThrow({
      where: { id },
      include: {
        subscription: true,
        planAssignment: { select: { plan: { select: { name: true } } } },
        websiteConfig: { select: { mode: true, status: true } },
        organization: {
          select: {
            id: true,
            name: true,
            memberships: {
              select: {
                account: {
                  select: {
                    id: true,
                    email: true,
                    displayName: true,
                    emailVerifiedAt: true,
                    isActive: true,
                  },
                },
              },
            },
          },
        },
      },
    });
    const managers = await this.commercial.managers(id);
    const devices = await this.db.device.findMany({
      where: { venueId: id },
      select: {
        id: true,
        displayName: true,
        status: true,
        lastSeenAt: true,
        firstSyncAt: true,
        runtimeConfig: true,
      },
    });
    const [menu, tables, sales] = await Promise.all([
      this.db.menuItem.count({ where: { venueId: id } }),
      this.db.table.count({ where: { venueId: id } }),
      this.db.cloudSale.count({ where: { venueId: id } }),
    ]);
    const enrollment = await this.enrollments.list(id);
    return {
      venue: {
        menuAuthority: venue.menuAuthority,
        id: venue.id,
        name: venue.name,
        branchName: venue.branchName,
        address: venue.address,
        phone: venue.phone,
        legalId: venue.legalId,
        profileUpdatedAt: venue.profileUpdatedAt,
        status: venue.status,
        activeOperationalDeviceId: venue.activeOperationalDeviceId,
        loginCode: features.includes('MANAGER_APP') ? venue.loginCode : null,
        timezone: venue.timezone,
        currency: venue.currency,
      },
      organization: {
        id: venue.organization.id,
        name: venue.organization.name,
        accounts: venue.organization.memberships.map((m) => m.account),
      },
      website: venue.websiteConfig,
      plan: venue.planAssignment && { name: venue.planAssignment.plan.name },
      subscription: venue.subscription
        ? {
            status: venue.subscription.status,
            trialEndsAt: venue.subscription.trialEndsAt,
          }
        : {
            status: venue.legacyCommercialAccess ? 'LEGACY' : 'NO_PLAN',
            trialEndsAt: null,
          },
      features,
      managers: features.includes('MANAGER_APP') ? managers : [],
      devices: (features.includes('POS') ? devices : []).map((device) => ({
        ...device,
        isOperationalPrimary: device.id === venue.activeOperationalDeviceId,
      })),
      enrollments: features.includes('POS') ? enrollment : [],
      ready:
        venue.status === 'ACTIVE' &&
        (!features.includes('MANAGER_APP') ||
          managers.some((m) => m.isActive)) &&
        (!features.includes('POS') ||
          devices.some(
            (d) =>
              d.id === venue.activeOperationalDeviceId &&
              d.status === 'ACTIVE' &&
              d.firstSyncAt,
          )),
      checklist: {
        restaurant: true,
        manager: managers.some((m) => m.isActive),
        code: true,
        enrollment: enrollment.length > 0,
        connected: devices.some(
          (d) =>
            d.id === venue.activeOperationalDeviceId &&
            d.status === 'ACTIVE' &&
            d.lastSeenAt &&
            Date.now() - d.lastSeenAt.getTime() < 120000,
        ),
        printers: devices.some((d) => d.runtimeConfig != null),
        menu: menu > 0,
        tables: tables > 0,
        firstSale: sales > 0,
      },
    };
  }
  async createVenue(actor: CustomerPrincipal, body: Record<string, unknown>) {
    const name = requireText(body.name, 'Restaurant name', { max: 100 });
    const timezone = requireText(body.timezone ?? 'Asia/Tbilisi', 'timezone');
    try {
      new Intl.DateTimeFormat('en', { timeZone: timezone });
    } catch {
      throw new BadRequestException('Invalid timezone');
    }
    const currency = requireText(
      body.currency ?? 'GEL',
      'currency',
    ).toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency))
      throw new BadRequestException('Currency must be an ISO code');
    return this.db.$transaction(async (tx) => {
      const memberships = await tx.organizationMembership.findMany({
        where: {
          customerAccountId: actor.customerAccountId,
          role: 'OWNER',
          ...(body.organizationId
            ? {
                organizationId: requireText(
                  body.organizationId,
                  'organizationId',
                ),
              }
            : {}),
        },
      });
      if (memberships.length !== 1)
        throw new BadRequestException('Choose an Organization you own');
      const organizationId = memberships[0].organizationId;
      await tx.$queryRaw`SELECT "id" FROM "pos"."Organization" WHERE "id"=${organizationId} FOR UPDATE`;
      const existing = await tx.venue.findFirst({
        where: { organizationId },
      });
      if (existing) return existing; // One restaurant per pilot Organization; request retry is convergent.
      const venue = await tx.venue.create({
        data: {
          organizationId,
          ...profileInput({ ...body, name }),
          profileUpdatedAt: new Date(),
          timezone,
          currency,
          subscription: { create: { status: 'NO_PLAN' } },
        },
      });
      await tx.customerAuditEvent.create({
        data: {
          customerAccountId: actor.customerAccountId,
          action: 'venue.created',
          targetType: 'Venue',
          targetId: venue.id,
        },
      });
      return venue;
    });
  }
  async manager(
    actor: CustomerPrincipal,
    venueId: string,
    action: 'create' | 'reset' | 'disable',
    body: Record<string, unknown>,
    staffId?: string,
  ) {
    await this.venue(actor, venueId);
    if (
      action !== 'disable' &&
      !(await this.entitlements.hasFeature(venueId, 'MANAGER_APP'))
    )
      throw new ForbiddenException('Manager is not included in this plan');
    return this.commercial.managerAccess(actor, venueId, action, body, staffId);
  }
  async enrollment(actor: CustomerPrincipal, venueId: string) {
    await this.venue(actor, venueId);
    if (!(await this.entitlements.hasFeature(venueId, 'POS')))
      throw new ForbiddenException('POS is not included in this plan');
    return this.enrollments.create(actor, venueId, {
      displayName: 'Main POS',
      platform: 'WINDOWS',
    });
  }
  async cancel(actor: CustomerPrincipal, venueId: string, id: string) {
    await this.venue(actor, venueId);
    return this.enrollments.cancel(actor, venueId, id);
  }
  async printers(
    actor: ControlActor,
    venueId: string,
    deviceId: string,
    body: Record<string, unknown>,
  ) {
    if (actor.customerAccountId)
      await this.venue({ customerAccountId: actor.customerAccountId }, venueId);
    await requireCommercialFeature(this.db, venueId, 'POS');
    const printers = Object.fromEntries(
      ['kitchen', 'receipt'].map((key) => {
        const row = body[key] as Record<string, unknown> | undefined;
        if (!row || typeof row.enabled !== 'boolean')
          throw new BadRequestException(`${key}.enabled is required`);
        const host = typeof row.host === 'string' ? row.host.trim() : '';
        if (
          (row.enabled && !host) ||
          host.length > 253 ||
          (host && !/^[a-zA-Z0-9.:[\]-]+$/.test(host))
        )
          throw new BadRequestException('Invalid printer host');
        const port = row.port ?? 9100;
        if (!Number.isInteger(port) || Number(port) < 1 || Number(port) > 65535)
          throw new BadRequestException('Invalid printer port');
        return [key, { enabled: row.enabled, host, port }];
      }),
    );
    return this.db.$transaction(async (tx) => {
      await requireCommercialFeature(tx, venueId, 'POS');
      const device = await tx.device.findFirst({
        where: { id: deviceId, venueId },
      });
      if (!device) throw new NotFoundException('Device not found');
      const runtimeConfig = { version: 1, printers };
      await tx.device.update({
        where: { id: deviceId },
        data: { runtimeConfig },
      });
      const data = {
        action: 'device.printers_changed',
        targetType: 'Device',
        targetId: deviceId,
        metadata: {
          from: device.runtimeConfig ?? null,
          to: runtimeConfig,
        } as Prisma.InputJsonObject,
      };
      if (actor.customerAccountId)
        await tx.customerAuditEvent.create({
          data: { ...data, customerAccountId: actor.customerAccountId },
        });
      else
        await tx.platformAuditEvent.create({
          data: { ...data, platformUserId: actor.platformUserId! },
        });
      return runtimeConfig;
    });
  }
}
