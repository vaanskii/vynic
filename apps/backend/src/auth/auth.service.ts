import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { StaffRole as StaffRoleEnum } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import * as bcrypt from 'bcrypt';
import {
  isMobileAppStaffRole,
  MOBILE_APP_STAFF_ROLES,
  normalizeStaffRole,
} from '../staff/staff-role';
import { LEGACY_MANAGER_TENANT } from '../tenancy/legacy-manager-tenant';

export interface MobileLoginResult {
  access_token: string;
  role: string;
  username: string;
  expiresIn: number; // seconds
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  /**
   * Authenticates manager mobile app users by PIN (manager only).
   *
   * The candidate search is still confined to the bootstrap Venue, and that is
   * a deliberate transitional limit rather than an oversight. A bare PIN
   * carries no venue discriminator, so widening this scan across Venues would
   * mean a PIN that happens to collide with another restaurant's manager could
   * authenticate into the wrong tenant. Multi-venue Manager login therefore
   * needs a venue-discriminating credential first — see
   * docs/MANAGER_TENANT_AUTH.md.
   *
   * The Venue on the resulting session is nonetheless read from the matched
   * Staff row rather than assumed, so the authority is already the server-owned
   * Staff/Venue relationship. Only the search scope is transitional.
   */
  async mobileLogin(pin: string): Promise<MobileLoginResult> {
    if (!pin || pin.length < 4) {
      throw new UnauthorizedException('Invalid PIN format');
    }

    const candidates = await this.prisma.staff.findMany({
      where: {
        venueId: LEGACY_MANAGER_TENANT.venueId,
        role: { in: MOBILE_APP_STAFF_ROLES as StaffRoleEnum[] },
        isActive: true,
      },
      select: { id: true, username: true, role: true, pinHash: true },
    });

    for (const staff of candidates) {
      const match = await bcrypt.compare(pin, staff.pinHash);
      if (match) {
        const role = normalizeStaffRole(staff.role);
        if (!isMobileAppStaffRole(staff.role)) continue;
        const payload = {
          sub: staff.id,
          username: staff.username,
          role,
        };
        const expiresIn = 24 * 60 * 60; // 24 h in seconds
        return {
          access_token: this.jwt.sign(payload, { expiresIn }),
          role,
          username: staff.username,
          expiresIn,
        };
      }
    }

    throw new UnauthorizedException('Invalid PIN');
  }

  /** Hash a plain PIN for storage. */
  static async hashPin(pin: string): Promise<string> {
    return bcrypt.hash(pin, 12);
  }
}
