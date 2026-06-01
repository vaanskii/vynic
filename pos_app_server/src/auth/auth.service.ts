import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../prisma.service';
import * as bcrypt from 'bcrypt';

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
   * Authenticates a manager/admin by PIN.
   * Only ADMIN and MANAGER roles are allowed to access the mobile companion app.
   */
  async mobileLogin(pin: string): Promise<MobileLoginResult> {
    if (!pin || pin.length < 4) {
      throw new UnauthorizedException('Invalid PIN format');
    }

    const candidates = await (this.prisma as any).staff.findMany({
      where: { role: { in: ['ADMIN', 'MANAGER'] }, isActive: true },
    });

    for (const staff of candidates) {
      const match = await bcrypt.compare(pin, staff.pinHash as string);
      if (match) {
        const payload = {
          sub: staff.id as string,
          username: staff.username as string,
          role: staff.role as string,
        };
        const expiresIn = 24 * 60 * 60; // 24 h in seconds
        return {
          access_token: this.jwt.sign(payload, { expiresIn }),
          role: staff.role as string,
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
