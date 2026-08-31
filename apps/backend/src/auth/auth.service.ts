import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
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
   */
  async mobileLogin(pin: string): Promise<MobileLoginResult> {
    if (!pin || pin.length < 4) {
      throw new UnauthorizedException('Invalid PIN format');
    }

    const candidates = await (this.prisma as any).staff.findMany({
      where: {
        venueId: LEGACY_MANAGER_TENANT.venueId,
        role: { in: MOBILE_APP_STAFF_ROLES },
        isActive: true,
      },
    });

    for (const staff of candidates) {
      const match = await bcrypt.compare(pin, staff.pinHash as string);
      if (match) {
        const role = normalizeStaffRole(staff.role as string);
        if (!isMobileAppStaffRole(role)) continue;
        const payload = {
          sub: staff.id as string,
          username: staff.username as string,
          role,
        };
        const expiresIn = 24 * 60 * 60; // 24 h in seconds
        return {
          access_token: this.jwt.sign(payload, { expiresIn }),
          role,
          username: staff.username as string,
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
