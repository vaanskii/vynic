import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  DeviceStatus,
  FeatureOverrideEffect,
  VenueDomainStatus,
  VenueStatus,
  WebsiteMode,
} from '@prisma/client';
import { PlatformActor, type PlatformPrincipal } from './platform-auth-context';
import { PlatformAuthGuard } from './platform-auth.guard';
import { PlatformDeviceService } from './platform-device.service';
import { PlatformDirectoryService } from './platform-directory.service';
import { PlatformVenueConfigService } from './platform-venue-config.service';
import {
  optionalText,
  readPage,
  requireEnumValue,
  requireText,
  requireUuid,
} from './platform-validation';

const VENUE_STATUSES = [VenueStatus.ACTIVE, VenueStatus.DISABLED] as const;
const DEVICE_STATUSES = [
  DeviceStatus.ACTIVE,
  DeviceStatus.DISABLED,
  DeviceStatus.REVOKED,
] as const;
const DOMAIN_STATUSES = [
  VenueDomainStatus.ACTIVE,
  VenueDomainStatus.DISABLED,
] as const;
const WEBSITE_MODES = [
  WebsiteMode.NONE,
  WebsiteMode.SAAS,
  WebsiteMode.CUSTOM,
] as const;
const OVERRIDE_EFFECTS = [
  FeatureOverrideEffect.ENABLED,
  FeatureOverrideEffect.DISABLED,
] as const;

/**
 * Venues and everything configured on them.
 *
 * Thin by design: each handler validates its input and calls one service. The
 * rules — precedence, normalization, uniqueness, audit — live in the services,
 * next to the invariants they protect.
 */
@Controller('platform/venues')
@UseGuards(PlatformAuthGuard)
export class PlatformVenuesController {
  constructor(
    private readonly directory: PlatformDirectoryService,
    private readonly config: PlatformVenueConfigService,
    private readonly devices: PlatformDeviceService,
  ) {}

  @Get()
  async list(
    @Query()
    query: {
      limit?: string;
      offset?: string;
      organizationId?: string;
    },
  ) {
    return this.directory.listVenues(
      readPage(query),
      query.organizationId
        ? requireUuid(query.organizationId, 'organizationId')
        : undefined,
    );
  }

  @Post()
  async create(
    @PlatformActor() actor: PlatformPrincipal,
    @Body()
    body: {
      organizationId?: unknown;
      name?: unknown;
      timezone?: unknown;
      currency?: unknown;
    },
  ) {
    return this.directory.createVenue(actor, {
      organizationId: requireUuid(body.organizationId, 'organizationId'),
      name: requireText(body.name, 'name'),
      timezone: requireText(body.timezone, 'timezone', { max: 64 }),
      currency: requireText(body.currency, 'currency', { min: 3, max: 3 }),
    });
  }

  @Get(':venueId')
  async read(@Param('venueId') venueId: string) {
    return this.directory.getVenue(requireUuid(venueId, 'venueId'));
  }

  @Patch(':venueId')
  async update(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: { name?: unknown; timezone?: unknown; currency?: unknown },
  ) {
    return this.directory.updateVenue(actor, requireUuid(venueId, 'venueId'), {
      name: optionalText(body.name, 'name'),
      timezone: optionalText(body.timezone, 'timezone', { max: 64 }),
      currency: optionalText(body.currency, 'currency', { min: 3, max: 3 }),
    });
  }

  @Put(':venueId/status')
  async setStatus(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: { status?: unknown },
  ) {
    return this.directory.setVenueStatus(
      actor,
      requireUuid(venueId, 'venueId'),
      requireEnumValue(body.status, VENUE_STATUSES, 'status'),
    );
  }

  // ── Product ───────────────────────────────────────────────────────────────

  @Get(':venueId/product')
  async readProduct(@Param('venueId') venueId: string) {
    return this.config.readProduct(requireUuid(venueId, 'venueId'));
  }

  @Put(':venueId/plan')
  async assignPlan(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: { planId?: unknown },
  ) {
    return this.config.assignPlan(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(body.planId, 'planId'),
    );
  }

  @Put(':venueId/features/:featureKey')
  async setFeatureOverride(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('featureKey') featureKey: string,
    @Body() body: { effect?: unknown; note?: unknown },
  ) {
    return this.config.setFeatureOverride(
      actor,
      requireUuid(venueId, 'venueId'),
      requireText(featureKey, 'featureKey', { max: 64 }).toUpperCase(),
      requireEnumValue(body.effect, OVERRIDE_EFFECTS, 'effect'),
      optionalText(body.note, 'note', { max: 500 }),
    );
  }

  @Delete(':venueId/features/:featureKey')
  async clearFeatureOverride(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('featureKey') featureKey: string,
  ) {
    return this.config.clearFeatureOverride(
      actor,
      requireUuid(venueId, 'venueId'),
      requireText(featureKey, 'featureKey', { max: 64 }).toUpperCase(),
    );
  }

  @Put(':venueId/website')
  async setWebsiteMode(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: { mode?: unknown },
  ) {
    return this.config.setWebsiteMode(
      actor,
      requireUuid(venueId, 'venueId'),
      requireEnumValue(body.mode, WEBSITE_MODES, 'mode'),
    );
  }

  // ── Domains ───────────────────────────────────────────────────────────────

  @Get(':venueId/domains')
  async listDomains(@Param('venueId') venueId: string) {
    return this.config.listDomains(requireUuid(venueId, 'venueId'));
  }

  @Post(':venueId/domains')
  async registerDomain(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: { hostname?: unknown },
  ) {
    return this.config.registerDomain(
      actor,
      requireUuid(venueId, 'venueId'),
      requireText(body.hostname, 'hostname', { max: 253 }),
    );
  }

  @Put(':venueId/domains/:domainId/status')
  async setDomainStatus(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('domainId') domainId: string,
    @Body() body: { status?: unknown },
  ) {
    return this.config.setDomainStatus(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(domainId, 'domainId'),
      requireEnumValue(body.status, DOMAIN_STATUSES, 'status'),
    );
  }

  @Delete(':venueId/domains/:domainId')
  async releaseDomain(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('domainId') domainId: string,
  ) {
    return this.config.releaseDomain(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(domainId, 'domainId'),
    );
  }

  // ── Devices ───────────────────────────────────────────────────────────────

  @Get(':venueId/devices')
  async listDevices(@Param('venueId') venueId: string) {
    return this.devices.listDevices(requireUuid(venueId, 'venueId'));
  }

  @Get(':venueId/devices/:deviceId')
  async readDevice(
    @Param('venueId') venueId: string,
    @Param('deviceId') deviceId: string,
  ) {
    return this.devices.getDevice(
      requireUuid(venueId, 'venueId'),
      requireUuid(deviceId, 'deviceId'),
    );
  }

  /** The response carries the credential. It is the only time it exists. */
  @Post(':venueId/devices')
  async createDevice(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body()
    body: {
      displayName?: unknown;
      platform?: unknown;
      installationId?: unknown;
    },
  ) {
    return this.devices.createDevice(actor, requireUuid(venueId, 'venueId'), {
      displayName: requireText(body.displayName, 'displayName'),
      platform: requireText(body.platform, 'platform', { max: 32 }),
      installationId:
        body.installationId === undefined
          ? undefined
          : requireUuid(body.installationId, 'installationId'),
    });
  }

  @Put(':venueId/devices/:deviceId/status')
  async setDeviceStatus(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('deviceId') deviceId: string,
    @Body() body: { status?: unknown },
  ) {
    return this.devices.setDeviceStatus(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(deviceId, 'deviceId'),
      requireEnumValue(body.status, DEVICE_STATUSES, 'status'),
    );
  }

  /** Replaces the secret. The previous one stops working immediately. */
  @Post(':venueId/devices/:deviceId/credential')
  async rotateCredential(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('deviceId') deviceId: string,
  ) {
    return this.devices.rotateCredential(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(deviceId, 'deviceId'),
    );
  }

  /** Queues a NOOP to check a machine is reachable. No other type is offered. */
  @Post(':venueId/test-command')
  async enqueueTestCommand(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: { deviceId?: unknown },
  ) {
    return this.devices.enqueueTestCommand(
      actor,
      requireUuid(venueId, 'venueId'),
      body.deviceId === undefined || body.deviceId === null
        ? undefined
        : requireUuid(body.deviceId, 'deviceId'),
    );
  }
}
