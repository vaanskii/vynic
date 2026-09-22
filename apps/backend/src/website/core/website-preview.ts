import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma.service';
import { requireEnv } from '../../shared/require-env';

/**
 * Short-lived authority to render one Venue's *draft* website.
 *
 * Owner preview shows the real generic frontend, which means the frontend needs
 * to ask the backend for draft content. Handing it the owner's portal JWT would
 * put a full account credential into a public product's storage and request
 * path, so a separate, narrower token is issued instead: one Venue, one
 * purpose, a short life, and no ability to reach any owner route.
 *
 * The token is its own audience and principal type, so it can neither be used
 * as a customer session nor produced by one being replayed. Ownership is proved
 * again when it is redeemed: a revoked account or a Venue that has moved is
 * refused even while an already-issued token is still inside its window.
 */
export const WEBSITE_PREVIEW_AUDIENCE = 'vynic-website-preview';
export const WEBSITE_PREVIEW_TTL_SECONDS = 1800;

export interface WebsitePreviewPrincipal {
  venueId: string;
  customerAccountId: string;
}

@Injectable()
export class WebsitePreviewTokens {
  constructor(
    private readonly db: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  async issue(venueId: string, customerAccountId: string) {
    const token = await this.jwt.signAsync(
      { sub: customerAccountId, typ: 'WEBSITE_PREVIEW', venueId },
      {
        secret: requireEnv('JWT_SECRET'),
        audience: WEBSITE_PREVIEW_AUDIENCE,
        issuer: 'vynic',
        expiresIn: WEBSITE_PREVIEW_TTL_SECONDS,
      },
    );
    return {
      token,
      expiresAt: new Date(
        Date.now() + WEBSITE_PREVIEW_TTL_SECONDS * 1000,
      ).toISOString(),
    };
  }

  async resolve(token: string): Promise<WebsitePreviewPrincipal> {
    try {
      const payload: unknown = await this.jwt.verifyAsync(token, {
        secret: requireEnv('JWT_SECRET'),
        audience: WEBSITE_PREVIEW_AUDIENCE,
        issuer: 'vynic',
      });
      // Claims are read as unknown and narrowed: a verified signature proves
      // who issued the token, not that its contents are the shape expected.
      const claims = (payload ?? {}) as Record<string, unknown>;
      if (
        claims.typ !== 'WEBSITE_PREVIEW' ||
        typeof claims.venueId !== 'string' ||
        typeof claims.sub !== 'string'
      )
        throw new Error('Wrong principal');
      const account = await this.db.customerAccount.findUnique({
        where: { id: claims.sub },
        select: { id: true, isActive: true },
      });
      if (!account?.isActive) throw new Error('Inactive account');
      // Re-proved, not trusted from the token: a Venue can change hands.
      const venue = await this.db.venue.findFirst({
        where: {
          id: claims.venueId,
          organization: {
            memberships: {
              some: { customerAccountId: account.id, role: 'OWNER' },
            },
          },
        },
        select: { id: true },
      });
      if (!venue) throw new Error('Venue is not owned by this account');
      return { venueId: venue.id, customerAccountId: account.id };
    } catch {
      throw new UnauthorizedException('Website preview authorization required');
    }
  }
}
