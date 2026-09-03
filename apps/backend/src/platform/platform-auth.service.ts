import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PlatformUserStatus } from '@prisma/client';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma.service';
import { requireEnv } from '../shared/require-env';
import {
  PLATFORM_PRINCIPAL_TYPE,
  PLATFORM_TOKEN_AUDIENCE,
  PLATFORM_TOKEN_ISSUER,
  type PlatformPrincipal,
} from './platform-auth-context';

export interface PlatformLoginResult {
  access_token: string;
  expiresIn: number;
  actor: PlatformPrincipal;
}

interface PlatformTokenPayload {
  sub: string;
  typ: string;
}

/** Eight hours: an administrative session, not a POS shift. */
const TOKEN_TTL_SECONDS = 8 * 60 * 60;

/**
 * Authentication for Vynic administrators.
 *
 * Separate from Manager and website authentication in three independent ways,
 * because one would not be enough:
 *
 *   1. the token is issued for the `vynic-platform` audience, which the JWT
 *      library itself refuses to accept for a token that lacks it;
 *   2. it carries an explicit principal type, which no other token has;
 *   3. its subject is resolved against PlatformUser, so a Staff id or a
 *      WebsiteUser id names nothing here.
 *
 * A Manager or customer token fails all three, so replaying one at a
 * control-plane route is not a matter of route prefixes.
 */
@Injectable()
export class PlatformAuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  /**
   * The signing key for platform tokens.
   *
   * `PLATFORM_JWT_SECRET` when the deployment sets one, otherwise the existing
   * `JWT_SECRET`. Optional on purpose: the separation above does not depend on a
   * distinct key, so requiring a new secret would be a deployment break for
   * defence the design already has. Setting one adds a layer and needs no code
   * change.
   */
  private get secret(): string {
    const dedicated = this.config.get<string>('PLATFORM_JWT_SECRET')?.trim();
    return dedicated && dedicated.length > 0
      ? dedicated
      : requireEnv('JWT_SECRET');
  }

  /**
   * Verifies an email and password.
   *
   * A wrong email and a wrong password are reported identically, so the
   * response cannot be used to enumerate administrators. A disabled account is
   * refused before its password is even checked.
   */
  async login(
    rawEmail: string,
    password: string,
  ): Promise<PlatformLoginResult> {
    const email = normalizeEmail(rawEmail);
    const denied = new UnauthorizedException('Invalid credentials');
    if (!email || !password) throw denied;

    const user = await this.prisma.platformUser.findUnique({
      where: { email },
      select: {
        id: true,
        email: true,
        displayName: true,
        role: true,
        status: true,
        passwordHash: true,
      },
    });
    if (!user || user.status !== PlatformUserStatus.ACTIVE) throw denied;
    if (!(await argon2.verify(user.passwordHash, password))) throw denied;

    await this.prisma.platformUser.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });

    const actor: PlatformPrincipal = {
      platformUserId: user.id,
      email: user.email,
      displayName: user.displayName,
      role: user.role,
    };

    return {
      access_token: await this.jwt.signAsync(
        { sub: user.id, typ: PLATFORM_PRINCIPAL_TYPE },
        {
          secret: this.secret,
          expiresIn: TOKEN_TTL_SECONDS,
          audience: PLATFORM_TOKEN_AUDIENCE,
          issuer: PLATFORM_TOKEN_ISSUER,
        },
      ),
      expiresIn: TOKEN_TTL_SECONDS,
      actor,
    };
  }

  /**
   * Resolves a bearer token to a live administrator, or null.
   *
   * Everything but the subject is re-read from the database, so disabling an
   * account takes effect on the next request rather than when its token
   * eventually expires.
   */
  async resolve(token: string): Promise<PlatformPrincipal | null> {
    let payload: PlatformTokenPayload;
    try {
      payload = await this.jwt.verifyAsync<PlatformTokenPayload>(token, {
        secret: this.secret,
        audience: PLATFORM_TOKEN_AUDIENCE,
        issuer: PLATFORM_TOKEN_ISSUER,
      });
    } catch {
      return null;
    }
    if (payload.typ !== PLATFORM_PRINCIPAL_TYPE) return null;

    const user = await this.prisma.platformUser.findUnique({
      where: { id: payload.sub },
      select: {
        id: true,
        email: true,
        displayName: true,
        role: true,
        status: true,
      },
    });
    if (!user || user.status !== PlatformUserStatus.ACTIVE) return null;

    return {
      platformUserId: user.id,
      email: user.email,
      displayName: user.displayName,
      role: user.role,
    };
  }
}

/** One comparable form for a login identifier. */
export function normalizeEmail(raw: string | null | undefined): string {
  return (raw ?? '').trim().toLowerCase();
}
