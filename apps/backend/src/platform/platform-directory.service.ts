import { Injectable, NotFoundException } from '@nestjs/common';
import { VenueStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { PlatformPrincipal } from './platform-auth-context';
import {
  PlatformAuditAction,
  PlatformAuditService,
} from './platform-audit.service';
import type { Page } from './platform-validation';

export interface CreateOrganizationInput {
  name: string;
}

export interface CreateVenueInput {
  organizationId: string;
  name: string;
  timezone: string;
  currency: string;
}

const ORGANIZATION_FIELDS = {
  id: true,
  name: true,
  createdAt: true,
  updatedAt: true,
} as const;

const VENUE_FIELDS = {
  id: true,
  organizationId: true,
  name: true,
  status: true,
  timezone: true,
  currency: true,
  createdAt: true,
  updatedAt: true,
} as const;

/**
 * Organizations and Venues, as the platform sees them.
 *
 * Cross-tenant by design and by a different route than every other reader in
 * this codebase: there is no TenantContext here, and none is faked. A platform
 * administrator is not standing inside the bootstrap Venue looking out.
 *
 * There is no delete. Organization and Venue are referenced by orders, tables,
 * staff, devices, bookings and domains under restrictive foreign keys, so
 * deleting one either fails or would have to cascade through a restaurant's
 * entire history. Disabling a Venue is the reversible operation that answers
 * the real need; removing data is not something a control-plane API should make
 * easy, and it is deliberately absent rather than half-guarded.
 */
@Injectable()
export class PlatformDirectoryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: PlatformAuditService,
  ) {}

  async listOrganizations(page: Page) {
    const [total, items] = await Promise.all([
      this.prisma.organization.count(),
      this.prisma.organization.findMany({
        select: {
          ...ORGANIZATION_FIELDS,
          _count: { select: { venues: true } },
        },
        orderBy: [{ name: 'asc' }, { id: 'asc' }],
        take: page.limit,
        skip: page.offset,
      }),
    ]);
    return { total, limit: page.limit, offset: page.offset, items };
  }

  async getOrganization(organizationId: string) {
    const organization = await this.prisma.organization.findUnique({
      where: { id: organizationId },
      select: {
        ...ORGANIZATION_FIELDS,
        venues: { select: VENUE_FIELDS, orderBy: { name: 'asc' } },
      },
    });
    if (!organization) throw new NotFoundException('Organization not found');
    return organization;
  }

  async createOrganization(
    actor: PlatformPrincipal,
    input: CreateOrganizationInput,
  ) {
    const organization = await this.prisma.organization.create({
      data: { name: input.name },
      select: ORGANIZATION_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.ORGANIZATION_CREATED,
      { type: 'Organization', id: organization.id },
      { name: organization.name },
    );
    return organization;
  }

  async updateOrganization(
    actor: PlatformPrincipal,
    organizationId: string,
    input: { name?: string },
  ) {
    await this.requireOrganization(organizationId);
    const organization = await this.prisma.organization.update({
      where: { id: organizationId },
      data: { name: input.name },
      select: ORGANIZATION_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.ORGANIZATION_UPDATED,
      { type: 'Organization', id: organization.id },
      { name: organization.name },
    );
    return organization;
  }

  async listVenues(page: Page, organizationId?: string) {
    const where = organizationId ? { organizationId } : undefined;
    const [total, items] = await Promise.all([
      this.prisma.venue.count({ where }),
      this.prisma.venue.findMany({
        where,
        select: VENUE_FIELDS,
        orderBy: [{ name: 'asc' }, { id: 'asc' }],
        take: page.limit,
        skip: page.offset,
      }),
    ]);
    return { total, limit: page.limit, offset: page.offset, items };
  }

  async getVenue(venueId: string) {
    const venue = await this.prisma.venue.findUnique({
      where: { id: venueId },
      select: {
        ...VENUE_FIELDS,
        organization: { select: { id: true, name: true } },
      },
    });
    if (!venue) throw new NotFoundException('Venue not found');
    return venue;
  }

  /**
   * Creates a Venue and nothing else.
   *
   * No tables, no menu, no device, no domain, no plan. Every one of those is a
   * separate deliberate act with its own audit row, and inventing them here
   * would put fabricated data in a real restaurant's account on day one.
   *
   * The id is generated. The deterministic bootstrap ids belong to the existing
   * Vankisi installation and must never be handed to a second customer.
   */
  async createVenue(actor: PlatformPrincipal, input: CreateVenueInput) {
    await this.requireOrganization(input.organizationId);

    const venue = await this.prisma.venue.create({
      data: {
        organizationId: input.organizationId,
        name: input.name,
        timezone: input.timezone,
        currency: input.currency,
      },
      select: VENUE_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.VENUE_CREATED,
      { type: 'Venue', id: venue.id },
      { name: venue.name, organizationId: venue.organizationId },
    );
    return venue;
  }

  async updateVenue(
    actor: PlatformPrincipal,
    venueId: string,
    input: { name?: string; timezone?: string; currency?: string },
  ) {
    await this.requireVenue(venueId);
    const venue = await this.prisma.venue.update({
      where: { id: venueId },
      data: {
        name: input.name,
        timezone: input.timezone,
        currency: input.currency,
      },
      select: VENUE_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.VENUE_UPDATED,
      { type: 'Venue', id: venue.id },
      { name: venue.name, timezone: venue.timezone, currency: venue.currency },
    );
    return venue;
  }

  /**
   * Enables or disables a Venue.
   *
   * A disabled Venue stops authenticating its Devices and stops resolving its
   * website host — both already enforced by DeviceCredentialService and
   * WebsiteTenantService, which read Venue.status directly. This changes one
   * column; the consequences were built in earlier phases.
   */
  async setVenueStatus(
    actor: PlatformPrincipal,
    venueId: string,
    status: VenueStatus,
  ) {
    const existing = await this.requireVenue(venueId);
    if (existing.status === status) return existing;

    const venue = await this.prisma.venue.update({
      where: { id: venueId },
      data: { status },
      select: VENUE_FIELDS,
    });
    await this.audit.record(
      actor,
      PlatformAuditAction.VENUE_STATUS_CHANGED,
      { type: 'Venue', id: venue.id },
      { from: existing.status, to: venue.status },
    );
    return venue;
  }

  private async requireOrganization(organizationId: string) {
    const organization = await this.prisma.organization.findUnique({
      where: { id: organizationId },
      select: { id: true },
    });
    if (!organization) throw new NotFoundException('Organization not found');
    return organization;
  }

  async requireVenue(venueId: string) {
    const venue = await this.prisma.venue.findUnique({
      where: { id: venueId },
      select: VENUE_FIELDS,
    });
    if (!venue) throw new NotFoundException('Venue not found');
    return venue;
  }
}
