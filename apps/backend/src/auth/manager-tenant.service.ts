import { Injectable } from '@nestjs/common';
import { VenueStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { isMobileAppStaffRole, normalizeStaffRole } from '../staff/staff-role';
import type { ManagerAuthContext } from './manager-auth-context';

/**
 * Resolves an authenticated Manager principal from a Staff identifier.
 *
 * This is the authority for Manager tenancy. The Venue comes from the Staff
 * row's own `venueId` — a relationship the server owns — and the Organization
 * from that Venue. Nothing a client sends can influence the result.
 *
 * Resolution happens per request rather than being trusted from a token claim.
 * Manager tokens live 24 hours, and over that window a staff member can be
 * deactivated, demoted, renamed, or have their Venue disabled; a claim minted
 * at login would keep working through all of it. One indexed primary-key
 * lookup per request buys immediate effect for every one of those changes, and
 * leaves exactly one source of truth instead of a token and a database that
 * can disagree.
 */
@Injectable()
export class ManagerTenantService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveByStaffId(staffId: string): Promise<ManagerAuthContext | null> {
    if (!staffId) return null;

    const staff = await this.prisma.staff.findUnique({
      where: { id: staffId },
      select: {
        id: true,
        username: true,
        role: true,
        isActive: true,
        venue: { select: { id: true, organizationId: true, status: true } },
      },
    });

    if (
      !staff ||
      !staff.isActive ||
      !isMobileAppStaffRole(staff.role) ||
      staff.venue.status !== VenueStatus.ACTIVE
    ) {
      return null;
    }

    return {
      staffId: staff.id,
      username: staff.username,
      role: normalizeStaffRole(staff.role),
      venueId: staff.venue.id,
      organizationId: staff.venue.organizationId,
    };
  }
}
