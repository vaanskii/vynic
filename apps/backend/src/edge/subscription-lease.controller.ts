import {
  BadRequestException,
  Body,
  Controller,
  HttpCode,
  Post,
  ServiceUnavailableException,
  UseGuards,
} from '@nestjs/common';
import { createPrivateKey, sign } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { commercialState } from '../entitlements/commercial-state';
import { FeatureKeys } from '../entitlements/feature-keys';
import { EdgeDevice, type EdgeDeviceContext } from './edge-device-context';
import { EdgeDeviceGuard } from './edge-device.guard';

export const MAX_OFFLINE_MS = 24 * 60 * 60 * 1000;
export function leaseDecision(
  state: Awaited<ReturnType<typeof commercialState>>,
  now: number,
) {
  const subscription = state.venue.subscription;
  const isTrial =
    subscription?.status === 'TRIAL' ||
    (!!subscription?.trialEndsAt &&
      !subscription.currentPeriodEndsAt &&
      !['ACTIVE', 'PAST_DUE'].includes(subscription.status));
  const cutoff = isTrial
    ? subscription.trialEndsAt?.getTime()
    : subscription?.currentPeriodEndsAt?.getTime();
  const allowed =
    state.features.includes(FeatureKeys.POS) &&
    (cutoff == null || cutoff > now);
  return {
    status: allowed
      ? 'VALID'
      : cutoff != null && cutoff <= now
        ? 'EXPIRED'
        : 'REVOKED',
    kind: isTrial ? 'TRIAL' : 'SUBSCRIPTION',
    entitlementEndsAt: cutoff ?? null,
    deadline: allowed
      ? Math.min(now + MAX_OFFLINE_MS, cutoff ?? Infinity)
      : now,
  };
}

/** Infrastructure endpoint: expired customers can verify, sync and recover. */
@Controller('edge/subscription-lease')
@UseGuards(EdgeDeviceGuard)
export class SubscriptionLeaseController {
  constructor(private readonly prisma: PrismaService) {}

  @Post()
  @HttpCode(200)
  async issue(
    @EdgeDevice() auth: EdgeDeviceContext,
    @Body() body: { nonce?: unknown },
  ) {
    if (typeof body?.nonce !== 'string' || !/^[a-f0-9]{64}$/.test(body.nonce))
      throw new BadRequestException('A fresh 32-byte nonce is required');
    const pem = process.env.VYNIC_LICENSE_SIGNING_KEY;
    if (!pem)
      throw new ServiceUnavailableException('License signer is not configured');
    let key: ReturnType<typeof createPrivateKey>;
    try {
      key = createPrivateKey(pem);
      if (key.asymmetricKeyType !== 'ed25519') throw new Error();
    } catch {
      throw new ServiceUnavailableException('License signer is unavailable');
    }
    return this.prisma.$transaction(async (tx) => {
      // Serialize against the existing commercial lifecycle's Venue lock.
      await tx.$queryRaw`SELECT id FROM pos."Venue" WHERE id = ${auth.venueId} FOR UPDATE`;
      const device = await tx.device.findUniqueOrThrow({
        where: { id: auth.deviceId },
      });
      const now = Date.now();
      const state = await commercialState(tx, auth.venueId, new Date(now));
      const decision = leaseDecision(state, now);
      if (
        device.venueId !== auth.venueId ||
        device.status !== 'ACTIVE' ||
        state.venue.status !== 'ACTIVE'
      ) {
        decision.status = 'REVOKED';
        decision.deadline = now;
      }
      const payload = Buffer.from(
        JSON.stringify({
          version: 1,
          deviceId: device.id,
          venueId: auth.venueId,
          installationId: device.installationId,
          nonce: body.nonce,
          issuedAt: now,
          ...decision,
        }),
      ).toString('base64');
      return {
        payload,
        signature: sign(null, Buffer.from(payload, 'base64'), key).toString(
          'base64',
        ),
      };
    });
  }
}
