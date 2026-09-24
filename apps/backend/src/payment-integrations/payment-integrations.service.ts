import { requireCommercialFeature } from '../entitlements/commercial-state';
import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { FeatureKeys } from '../entitlements/feature-keys';
import {
  encryptPaymentConfig,
  decryptPaymentConfig,
} from './payment-config.crypto';
import type { Prisma } from '@prisma/client';

export type BogConfig = {
  clientId: string;
  clientSecret: string;
  returnOrigin: string;
};
export type PaymentActor =
  | { customerAccountId: string }
  | { importOperator: string };
@Injectable()
export class PaymentIntegrationsService {
  constructor(
    private readonly db: PrismaService,
    private readonly entitlements: VenueEntitlementsService,
  ) {}

  async status(venueId: string) {
    const row = await this.db.paymentIntegration.findFirst({
      where: { venueId, provider: 'BOG' },
      orderBy: { revision: 'desc' },
      select: { enabled: true, revision: true, createdAt: true },
    });
    return {
      provider: 'BOG',
      configured: !!row?.enabled,
      revision: row?.revision ?? null,
      updatedAt: row?.createdAt ?? null,
      entitled: await this.entitlements.hasFeature(
        venueId,
        FeatureKeys.ONLINE_PAYMENTS,
      ),
    };
  }
  async requireEnabled(venueId: string) {
    if (
      !(await this.entitlements.hasFeature(
        venueId,
        FeatureKeys.ONLINE_PAYMENTS,
      ))
    )
      throw new ForbiddenException('Online payments unavailable');
    const row = await this.db.paymentIntegration.findFirst({
      where: { venueId, provider: 'BOG', enabled: true },
    });
    if (!row) throw new ForbiddenException('Payment integration unavailable');
    const config = decryptPaymentConfig(
      venueId,
      row.id,
      row.encryptedConfig,
    ) as BogConfig;
    if (
      !(await this.db.venueDomain.findFirst({
        where: {
          venueId,
          hostname: new URL(config.returnOrigin).hostname,
          status: 'ACTIVE',
        },
      }))
    )
      throw new ForbiddenException('Payment return domain unavailable');
    return row;
  }
  async credentials(venueId: string, id: string): Promise<BogConfig> {
    const row = await this.db.paymentIntegration.findFirst({
      where: { id, venueId, provider: 'BOG' },
    });
    if (!row) throw new NotFoundException('Payment integration not found');
    return decryptPaymentConfig(venueId, id, row.encryptedConfig) as BogConfig;
  }
  private async validate(
    venueId: string,
    body: Record<string, unknown>,
  ): Promise<BogConfig> {
    const { clientId, clientSecret, returnOrigin } = body;
    if (
      Object.keys(body).some(
        (k) => !['clientId', 'clientSecret', 'returnOrigin'].includes(k),
      ) ||
      typeof clientId !== 'string' ||
      !clientId.trim() ||
      clientId.length > 512 ||
      typeof clientSecret !== 'string' ||
      !clientSecret.trim() ||
      clientSecret.length > 4096 ||
      typeof returnOrigin !== 'string'
    )
      throw new BadRequestException(
        'Client ID, Client Secret and return origin are required',
      );
    let origin: URL;
    try {
      origin = new URL(returnOrigin);
    } catch {
      throw new BadRequestException('Invalid return origin');
    }
    const local =
      process.env.NODE_ENV !== 'production' &&
      (origin.hostname === 'localhost' ||
        origin.hostname.endsWith('.localhost'));
    if (
      (origin.protocol !== 'https:' &&
        !(local && origin.protocol === 'http:')) ||
      origin.username ||
      origin.password ||
      origin.pathname !== '/' ||
      origin.search ||
      origin.hash
    )
      throw new BadRequestException(
        'Return origin must be an HTTPS website origin',
      );
    if (
      !(await this.db.venueDomain.findFirst({
        where: { venueId, hostname: origin.hostname, status: 'ACTIVE' },
      }))
    )
      throw new BadRequestException(
        'Return origin must belong to an active restaurant domain',
      );
    return {
      clientId: clientId.trim(),
      clientSecret,
      returnOrigin: origin.origin,
    };
  }
  private async audit(
    tx: Prisma.TransactionClient,
    venueId: string,
    actor: PaymentActor,
    action: string,
    revision: number,
  ) {
    const data = {
      action,
      targetType: 'PaymentIntegration',
      targetId: venueId,
      metadata: { provider: 'BOG', revision },
    };
    if ('customerAccountId' in actor)
      await tx.customerAuditEvent.create({
        data: { ...data, customerAccountId: actor.customerAccountId },
      });
    else
      await tx.auditEventLog.create({
        data: {
          venueId,
          entityType: 'PAYMENT_INTEGRATION',
          entityId: venueId,
          action,
          userId: actor.importOperator,
          deviceType: 'CLOUD',
          data: { provider: 'BOG', revision },
        },
      });
  }
  async save(
    venueId: string,
    body: Record<string, unknown>,
    actor: PaymentActor,
    importOnly = false,
  ) {
    if (!importOnly)
      await requireCommercialFeature(this.db, venueId, 'ONLINE_PAYMENTS');
    const config = await this.validate(venueId, body);
    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id" = ${venueId} FOR UPDATE`;
      if (!importOnly)
        await requireCommercialFeature(tx, venueId, 'ONLINE_PAYMENTS');
      const previous = await tx.paymentIntegration.findFirst({
        where: { venueId, provider: 'BOG' },
        orderBy: { revision: 'desc' },
      });
      if (importOnly && previous) {
        const old = decryptPaymentConfig(
          venueId,
          previous.id,
          previous.encryptedConfig,
        ) as BogConfig;
        if (!previous.enabled || JSON.stringify(old) !== JSON.stringify(config))
          throw new BadRequestException(
            'Integration already exists; import refuses to overwrite',
          );
        return;
      }
      const id = randomUUID(),
        revision = (previous?.revision ?? 0) + 1;
      const encryptedConfig = encryptPaymentConfig(venueId, id, config);
      await tx.paymentIntegration.updateMany({
        where: { venueId, provider: 'BOG', enabled: true },
        data: { enabled: false },
      });
      await tx.paymentIntegration.create({
        data: { id, venueId, provider: 'BOG', revision, encryptedConfig },
      });
      if (importOnly)
        await tx.websiteReservation.updateMany({
          where: {
            venueId,
            paymentIntegrationId: null,
            paymentId: { not: null },
          },
          data: { paymentIntegrationId: id },
        });
      await this.audit(
        tx,
        venueId,
        actor,
        importOnly
          ? 'payment_integration.imported'
          : 'payment_integration.updated',
        revision,
      );
    });
    return this.status(venueId);
  }
  async disable(venueId: string, actor: PaymentActor) {
    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id" = ${venueId} FOR UPDATE`;
      const current = await tx.paymentIntegration.findFirst({
        where: { venueId, provider: 'BOG', enabled: true },
      });
      if (!current) return;
      await tx.paymentIntegration.update({
        where: { id: current.id },
        data: { enabled: false },
      });
      await this.audit(
        tx,
        venueId,
        actor,
        'payment_integration.disabled',
        current.revision,
      );
    });
    return this.status(venueId);
  }
}
