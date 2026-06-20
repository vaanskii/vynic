import { ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { WebsiteUserRole } from '@prisma/client';
import { PrismaClientKnownRequestError } from '@prisma/client/runtime/library';
import { Request } from 'express';
import * as argon from 'argon2';
import { PrismaService } from '../../shared/prisma/prisma.service';
import { CryptoService } from '../common/crypto.service';
import { AuthDto, ChangePasswordDto, RegisterDto } from './dto';

export type WebsiteAuthUser = {
  id: string;
  phone: string;
  firstName: string | null;
  lastName: string | null;
  email: string | null;
  role: WebsiteUserRole;
};

@Injectable()
export class WebsiteAuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly crypto: CryptoService,
  ) {}

  private normalizeEmail(email: string): string {
    return email.trim().toLowerCase();
  }

  private async findUserByIdentifier(identifier: string) {
    const trimmed = identifier.trim();
    if (trimmed.includes('@')) {
      return this.prisma.websiteUser.findUnique({
        where: { email: this.normalizeEmail(trimmed) },
      });
    }
    return this.prisma.websiteUser.findUnique({
      where: { phone: trimmed },
    });
  }

  async signup(dto: RegisterDto): Promise<{
    access_token: string;
    refresh_token: string;
  }> {
    const password = await argon.hash(dto.password);
    const email = this.normalizeEmail(dto.email);

    try {
      const user = await this.prisma.websiteUser.create({
        data: {
          phone: dto.phone.trim(),
          email,
          password,
          firstName: dto.firstName?.trim() || null,
          lastName: dto.lastName?.trim() || null,
          role: WebsiteUserRole.USER,
        },
      });

      const tokens = await this.signToken(user.id, user.phone, user.role);
      await this.updateRefreshToken(user.id, tokens.refresh_token);
      return tokens;
    } catch (error) {
      if (error instanceof PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ForbiddenException('Phone number or email already exists');
      }
      throw error;
    }
  }

  async signin(dto: AuthDto): Promise<{
    access_token: string;
    refresh_token: string;
  }> {
    const user = await this.findUserByIdentifier(dto.identifier);
    if (!user) throw new ForbiddenException('Credentials incorrect');

    const passwordMatches = await argon.verify(user.password, dto.password);
    if (!passwordMatches) throw new ForbiddenException('Credentials incorrect');

    const tokens = await this.signToken(user.id, user.phone, user.role);
    await this.updateRefreshToken(user.id, tokens.refresh_token);
    return tokens;
  }

  async signToken(
    userId: string,
    phone: string,
    role: WebsiteUserRole,
  ): Promise<{ access_token: string; refresh_token: string }> {
    const payload = { sub: userId, phone, role };
    const [at, rt] = await Promise.all([
      this.jwt.signAsync(payload, {
        expiresIn: '15m',
        secret: this.config.get('JWT_SECRET'),
      }),
      this.jwt.signAsync(payload, {
        expiresIn: '7d',
        secret: this.config.get('JWT_REFRESH_SECRET'),
      }),
    ]);
    return { access_token: at, refresh_token: rt };
  }

  async updateRefreshToken(userId: string, refreshToken: string): Promise<void> {
    const hashedRefreshToken = await argon.hash(refreshToken);
    await this.prisma.websiteUser.update({
      where: { id: userId },
      data: { hashedRefreshToken },
    });
  }

  async verifyToken(token: string): Promise<WebsiteAuthUser> {
    try {
      const payload = await this.jwt.verifyAsync<{
        sub: string;
      }>(token, {
        secret: this.config.get('JWT_SECRET'),
      });

      const user = await this.prisma.websiteUser.findUnique({
        where: { id: payload.sub },
        select: {
          id: true,
          phone: true,
          firstName: true,
          lastName: true,
          email: true,
          role: true,
        },
      });

      if (!user) throw new ForbiddenException('User not found');
      return user;
    } catch {
      throw new ForbiddenException('Invalid token');
    }
  }

  /** Returns null when the request is anonymous or the cookie token is invalid. */
  async tryGetUserFromRequest(request: Request): Promise<WebsiteAuthUser | null> {
    const encryptedAccessToken = request.cookies?.access_token;
    if (typeof encryptedAccessToken !== 'string' || encryptedAccessToken.length === 0) {
      return null;
    }
    try {
      const accessToken = this.crypto.decrypt(encryptedAccessToken);
      return await this.verifyToken(accessToken);
    } catch {
      return null;
    }
  }

  async changePassword(userId: string, dto: ChangePasswordDto) {
    const user = await this.prisma.websiteUser.findUnique({ where: { id: userId } });
    if (!user) throw new ForbiddenException('User not found');

    const passwordMatches = await argon.verify(user.password, dto.oldPassword);
    if (!passwordMatches) throw new ForbiddenException('Incorrect password');

    const hash = await argon.hash(dto.newPassword);
    await this.prisma.websiteUser.update({
      where: { id: userId },
      data: { password: hash },
    });

    return { message: 'Password updated successfully' };
  }
}
