import {
  Body,
  ConflictException,
  Controller,
  Injectable,
  NotFoundException,
  Param,
  Post,
  ServiceUnavailableException,
  UseGuards,
} from '@nestjs/common';
import { createPrivateKey, sign } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import {
  PlatformActor,
  type PlatformPrincipal,
} from '../platform/platform-auth-context';
import { requireText, requireUuid } from '../platform/platform-validation';
import { lockOperationalVenue } from '../edge/operational-authority';

@Injectable()
export class EdgeFoundationService {
  constructor(private readonly db: PrismaService) {}

  async provision(
    actor: PlatformPrincipal,
    venueId: string,
    installationId: string,
    publicKey: string,
  ) {
    if (
      !/^[A-Za-z0-9_-]{43}$/.test(publicKey) ||
      Buffer.from(publicKey, 'base64url').toString('base64url') !== publicKey
    ) {
      throw new ConflictException(
        'A canonical raw Ed25519 public key is required',
      );
    }
    const pem = process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM;
    if (!pem)
      throw new ServiceUnavailableException(
        'Foundation provisioning is not configured',
      );
    let key: ReturnType<typeof createPrivateKey>;
    try {
      key = createPrivateKey(pem);
      if (key.asymmetricKeyType !== 'ed25519') throw Error('Wrong key type');
    } catch {
      throw new ServiceUnavailableException(
        'Invalid foundation signing configuration',
      );
    }
    return this.db.$transaction(async (tx) => {
      const venue = await lockOperationalVenue(tx, venueId);
      if (!venue || venue.status !== 'ACTIVE')
        throw new NotFoundException('Active Venue not found');
      // Serialize all registrations, including malicious reuse across Venues.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${installationId}))`;
      const old = await tx.edgeFoundationInstallation.findUnique({
        where: { id: installationId },
      });
      if (
        old &&
        (old.venueId !== venueId ||
          old.publicKey !== publicKey ||
          old.revokedAt)
      ) {
        throw new ConflictException(
          'Installation binding is immutable or revoked',
        );
      }
      if (!old) {
        const reused = await tx.edgeFoundationInstallation.findUnique({
          where: { publicKey },
        });
        if (reused)
          throw new ConflictException('Public key already registered');
        await tx.edgeFoundationInstallation.create({
          data: { id: installationId, venueId, publicKey },
        });
      }
      const issuedAt = Math.floor(Date.now() / 1000);
      const payload = Buffer.from(
        JSON.stringify({
          version: 1,
          purpose: 'vynic-edge-foundation',
          mode: 'FOUNDATION_ONLY',
          installationId,
          venueId,
          publicKey,
          issuedAt,
          expiresAt: issuedAt + 600,
        }),
      ).toString('base64url');
      const grant =
        payload +
        '.' +
        sign(null, Buffer.from(payload), key).toString('base64url');
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'edge.foundation_grant_issued',
          targetType: 'Venue',
          targetId: venueId,
          metadata: {
            installationId,
            mode: 'FOUNDATION_ONLY',
            reissued: Boolean(old),
          },
        },
      });
      return {
        grant,
        installationId,
        venueId,
        mode: 'FOUNDATION_ONLY',
        businessMutationsEnabled: false,
      };
    });
  }

  async revoke(
    actor: PlatformPrincipal,
    venueId: string,
    installationId: string,
  ) {
    return this.db.$transaction(async (tx) => {
      await lockOperationalVenue(tx, venueId);
      const row = await tx.edgeFoundationInstallation.findFirst({
        where: { id: installationId, venueId },
      });
      if (!row) throw new NotFoundException('Installation not found');
      if (!row.revokedAt) {
        await tx.edgeFoundationInstallation.update({
          where: { id: installationId },
          data: { revokedAt: new Date() },
        });
        await tx.platformAuditEvent.create({
          data: {
            platformUserId: actor.platformUserId,
            action: 'edge.foundation_revoked',
            targetType: 'Venue',
            targetId: venueId,
            metadata: { installationId },
          },
        });
      }
      return { installationId, revoked: true };
    });
  }
}

@Controller('platform/venues/:venueId/edge-foundations')
@UseGuards(PlatformAuthGuard)
export class EdgeFoundationController {
  constructor(private readonly service: EdgeFoundationService) {}

  @Post()
  provision(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: { installationId?: unknown; publicKey?: unknown },
  ) {
    return this.service.provision(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(body.installationId, 'installationId'),
      requireText(body.publicKey, 'publicKey', { max: 43 }),
    );
  }

  @Post(':installationId/revoke')
  revoke(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venueId: string,
    @Param('installationId') installationId: string,
  ) {
    return this.service.revoke(
      actor,
      requireUuid(venueId, 'venueId'),
      requireUuid(installationId, 'installationId'),
    );
  }
}
