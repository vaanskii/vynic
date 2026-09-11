import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { StaffRole as StaffRoleEnum } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import * as bcrypt from 'bcrypt';
import {
  MOBILE_APP_STAFF_ROLES,
  normalizeStaffRole,
} from '../staff/staff-role';
import { managerLoginContract } from '../shared/contracts/manager-login';

export interface MobileLoginResult {
  venueCode: string;
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

  /** Venue is selected before any PIN comparisons; duplicate matches fail closed. */
  async mobileLogin(
    pin: string,
    venueCode?: string,
  ): Promise<MobileLoginResult> {
    if (typeof pin !== 'string' || !/^\d{4,6}$/.test(pin)) {
      throw new UnauthorizedException('Invalid credentials');
    }
    let code: string;
    if (venueCode === undefined) {
      // Explicit, deadline-bounded support for already deployed PIN-only clients.
      const deadline = Date.parse(process.env.MANAGER_LEGACY_LOGIN_UNTIL ?? '');
      if (
        !Number.isFinite(deadline) ||
        Date.now() >= deadline ||
        deadline > Date.parse(managerLoginContract.legacyMaximumDeadline)
      ) {
        throw new UnauthorizedException(
          'Restaurant code required; update Manager',
        );
      }
      code = managerLoginContract.rolloutVenueCode;
    } else {
      if (typeof venueCode !== 'string')
        throw new UnauthorizedException('Invalid credentials');
      code = venueCode.trim().toLowerCase();
    }
    if (!new RegExp(managerLoginContract.venueCodePattern).test(code)) {
      throw new UnauthorizedException('Invalid credentials');
    }
    const venue = await this.prisma.venue.findUnique({
      where: { loginCode: code },
    });
    if (!venue || venue.status !== 'ACTIVE')
      throw new UnauthorizedException('Invalid credentials');
    const candidates = await this.prisma.staff.findMany({
      where: {
        venueId: venue.id,
        role: { in: MOBILE_APP_STAFF_ROLES as StaffRoleEnum[] },
        isActive: true,
      },
      select: { id: true, username: true, role: true, pinHash: true },
    });
    const matches: typeof candidates = [];
    for (const staff of candidates) {
      if (await bcrypt.compare(pin, staff.pinHash)) matches.push(staff);
    }
    if (matches.length !== 1)
      throw new UnauthorizedException('Invalid credentials');
    const staff = matches[0];
    const role = normalizeStaffRole(staff.role);
    const expiresIn = 24 * 60 * 60;
    return {
      access_token: this.jwt.sign(
        { sub: staff.id, username: staff.username, role },
        { expiresIn },
      ),
      role,
      username: staff.username,
      expiresIn,
      venueCode: venue.loginCode,
    };
  }

  /** Hash a plain PIN for storage. */
  static async hashPin(pin: string): Promise<string> {
    return bcrypt.hash(pin, 12);
  }
}
