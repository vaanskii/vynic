import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import {
  createPrivateKey,
  createPublicKey,
  randomUUID,
  sign,
} from 'node:crypto';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { lockOperationalVenue } from '../edge/operational-authority';
import type { PosAuthContext } from '../auth/pos-auth-context';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import {
  configuration,
  digest,
  emptyConfiguration,
  enrollment,
  id,
  integer,
  Member,
  object,
  OFFLINE_SECONDS,
  PURPOSE,
  retainBindings,
  signatureInput,
  type Configuration,
} from './contract';

function signer() {
  try {
    const pem = process.env.PRINTER_PRODUCTION_SIGNING_KEY_PEM;
    if (!pem) throw Error();
    const key = createPrivateKey(pem);
    if (key.asymmetricKeyType !== 'ed25519') throw Error();
    if (
      process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM &&
      createPublicKey(key).export({ format: 'jwk' }).x ===
        createPublicKey(
          createPrivateKey(process.env.EDGE_FOUNDATION_SIGNING_KEY_PEM),
        ).export({ format: 'jwk' }).x
    )
      throw Error();
    return key;
  } catch {
    throw new ServiceUnavailableException(
      'Independent production printer signer is not configured',
    );
  }
}

@Injectable()
export class PrinterProvisioningService {
  constructor(private readonly db: PrismaService) {}
  private async state(tx: Prisma.TransactionClient, venueId: string) {
    const venue = await lockOperationalVenue(tx, venueId);
    if (venue.status !== 'ACTIVE')
      throw new ForbiddenException('Active Venue required');
    // Existing Device status writers do not all lock Venue. Hold their rows
    // through issuance so revocation and the grant have a defined ordering.
    await tx.$queryRaw`SELECT id FROM pos."Device" WHERE "venueId"=${venueId} ORDER BY id FOR SHARE`;
    return tx.printerVenueAuthority.upsert({
      where: { venueId },
      create: {
        venueId,
        clusterId: randomUUID(),
        configuration: emptyConfiguration() as unknown as Prisma.InputJsonValue,
        fixedBindings: {},
      },
      update: {},
    });
  }
  private async members(
    tx: Prisma.TransactionClient,
    venueId: string,
    config: Configuration,
  ): Promise<Member[]> {
    // Device revocation is authoritative even when it used an older Device API.
    await tx.printerInstallation.updateMany({
      where: {
        venueId,
        revokedAt: null,
        device: { status: { not: 'ACTIVE' } },
      },
      data: { revokedAt: new Date() },
    });
    const rows = await tx.printerInstallation.findMany({
      where: { venueId },
      include: { device: true },
      orderBy: { id: 'asc' },
    });
    return rows.map((r) => ({
      installationId: r.id,
      deviceId: r.deviceId,
      publicKey: r.publicKey,
      certificateSha256: r.certificateSha256,
      authorized: r.revokedAt === null && r.device.status === 'ACTIVE',
      role: config.voters.includes(r.id) ? 'VOTER' : 'CLIENT',
      endpointHint: config.endpoints[r.id] ?? '',
    }));
  }
  async enroll(auth: PosAuthContext, input: unknown) {
    if (auth.authenticationMode !== 'device' || !auth.deviceId)
      throw new ForbiddenException('Device authority required');
    const b = enrollment(input, auth.deviceId);
    const key = signer(); // fail before persistence when deployment secrets are absent
    return this.db.$transaction(async (tx) => {
      const state = await this.state(tx, auth.venueId);
      const device = await tx.device.findFirst({
        where: { id: auth.deviceId!, venueId: auth.venueId, status: 'ACTIVE' },
      });
      if (
        !device ||
        device.platform.toUpperCase() !== 'WINDOWS' ||
        device.installationId === b.installationId ||
        device.id === b.installationId
      )
        throw new ForbiddenException(
          'Independent Windows Go identity required',
        );
      // Identity reuse is serialized across Venues; no caller-supplied tenant wins.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${b.installationId}))`;
      const old = await tx.printerInstallation.findUnique({
        where: { id: b.installationId },
      });
      const certificateSha256 = digest(Buffer.from(b.certificate, 'base64'));
      if (
        old &&
        (old.venueId !== auth.venueId ||
          old.deviceId !== device.id ||
          old.publicKey !== b.publicKey ||
          old.certificateSha256 !== certificateSha256 ||
          old.revokedAt)
      )
        throw new ConflictException(
          'Printer installation binding is immutable or revoked',
        );
      if (
        await tx.edgeFoundationInstallation.findFirst({
          where: { OR: [{ id: b.installationId }, { publicKey: b.publicKey }] },
        })
      )
        throw new ConflictException(
          'Foundation identity cannot become printer authority',
        );
      if (!old) {
        if (
          await tx.printerInstallation.findFirst({
            where: {
              OR: [
                { publicKey: b.publicKey },
                { certificateSha256 },
                { deviceId: device.id, revokedAt: null },
              ],
            },
          })
        )
          throw new ConflictException(
            'Printer identity already registered; revoke before replacement',
          );
        if (
          (await tx.printerInstallation.count({
            where: { venueId: auth.venueId },
          })) >= 256
        )
          throw new ConflictException('Printer inventory capacity reached');
        await tx.printerInstallation.create({
          data: {
            id: b.installationId,
            venueId: auth.venueId,
            deviceId: device.id,
            publicKey: b.publicKey,
            certificateSha256,
          },
        });
      }
      const c = state.configuration as unknown as Configuration;
      const members = await this.members(tx, auth.venueId, c);
      const now = Math.floor(Date.now() / 1000);
      integer(state.generation + 1, 1);
      const next = await tx.printerVenueAuthority.update({
        where: { venueId: auth.venueId },
        data: { generation: { increment: 1 } },
      });
      const body = Buffer.from(
        JSON.stringify({
          version: 1,
          purpose: PURPOSE,
          venueId: auth.venueId,
          clusterId: state.clusterId,
          generation: next.generation,
          revision: state.revision,
          issuedAt: now,
          notBefore: now,
          expiresAt: now + OFFLINE_SECONDS,
          offlineMaxSeconds: OFFLINE_SECONDS,
          topology: c.topology,
          members,
          catalogRaw:
            c.catalog === null
              ? ''
              : Buffer.from(JSON.stringify(c.catalog)).toString('base64'),
        }),
      );
      return {
        body: body.toString('base64'),
        signature: sign(null, signatureInput(body), key).toString('base64'),
      };
    });
  }
  async inventory(venueId: string) {
    return this.db.$transaction(async (tx) => {
      const s = await this.state(tx, id(venueId));
      return {
        revision: s.revision,
        clusterId: s.clusterId,
        configuration: s.configuration,
        members: await this.members(
          tx,
          venueId,
          s.configuration as unknown as Configuration,
        ),
      };
    });
  }
  async publish(actor: PlatformPrincipal, venueId: string, input: unknown) {
    const b = object(input, ['expectedRevision', 'configuration']);
    integer(b.expectedRevision);
    return this.db.$transaction(async (tx) => {
      const s = await this.state(tx, id(venueId));
      if (s.revision !== b.expectedRevision)
        throw new ConflictException('Printer configuration changed');
      integer(s.revision + 1, 1);
      const c = configuration(
        b.configuration,
        venueId,
        s.revision + 1,
        await this.members(
          tx,
          venueId,
          s.configuration as unknown as Configuration,
        ),
      );
      const fixedBindings = retainBindings(
        s.fixedBindings as Record<string, string>,
        c,
      );
      await tx.printerVenueAuthority.update({
        where: { venueId },
        data: {
          revision: s.revision + 1,
          configuration: c as unknown as Prisma.InputJsonValue,
          fixedBindings,
        },
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'printer.configuration_published',
          targetType: 'Venue',
          targetId: venueId,
          metadata: {
            revision: s.revision + 1,
            topology: c.topology,
            voters: c.voters,
          },
        },
      });
      return { revision: s.revision + 1, activation: 'NOT_ACTIVATED' };
    });
  }
  async revoke(
    actor: PlatformPrincipal,
    venueId: string,
    installationId: string,
  ) {
    return this.db.$transaction(async (tx) => {
      await this.state(tx, id(venueId));
      const row = await tx.printerInstallation.findFirst({
        where: { id: id(installationId), venueId },
      });
      if (!row) throw new NotFoundException('Printer installation not found');
      if (!row.revokedAt) {
        await tx.printerInstallation.update({
          where: { id: installationId },
          data: { revokedAt: new Date() },
        });
        await tx.platformAuditEvent.create({
          data: {
            platformUserId: actor.platformUserId,
            action: 'printer.installation_revoked',
            targetType: 'Venue',
            targetId: venueId,
            metadata: { installationId },
          },
        });
      }
      return { revoked: true, installationId };
    });
  }
}
