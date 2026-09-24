import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { requireText } from './platform-validation';
import type { PlatformPrincipal } from './platform-auth-context';
@Injectable()
export class PlanCatalogService {
  constructor(private readonly db: PrismaService) {}
  async save(
    actor: PlatformPrincipal,
    id: string | undefined,
    body: Record<string, unknown>,
  ) {
    const key = requireText(body.key, 'Key', { max: 80 });
    if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(key))
      throw new BadRequestException(
        'Use letters, numbers, underscores or hyphens for the plan key',
      );
    const name = requireText(body.name, 'Name', { max: 100 });
    const description = body.description
      ? requireText(body.description, 'Description', { max: 2000 })
      : null;
    const currency = requireText(body.currency, 'Currency').toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency))
      throw new BadRequestException('Invalid currency');
    if (!['MONTH', 'YEAR', 'ONE_TIME'].includes(String(body.billingPeriod)))
      throw new BadRequestException('Invalid billing period');
    if (!['ACTIVE', 'RETIRED'].includes(String(body.status)))
      throw new BadRequestException('Invalid plan status');
    const integer = (value: unknown, field: string, max: number) => {
      if (
        typeof value !== 'number' ||
        !Number.isInteger(value) ||
        value < 0 ||
        value > max
      )
        throw new BadRequestException(`Invalid ${field}`);
      return value;
    };
    const priceMinor = integer(body.priceMinor, 'price', 100000000);
    const mediaQuotaBytes = integer(
      body.mediaQuotaBytes ?? 52428800,
      'media byte quota',
      1073741824,
    );
    const mediaQuotaFiles = integer(
      body.mediaQuotaFiles ?? 50,
      'media file quota',
      1000,
    );
    if (
      !Array.isArray(body.featureKeys) ||
      body.featureKeys.some(
        (k) => typeof k !== 'string' || k === 'NON_FISCAL_CLOSE',
      )
    )
      throw new BadRequestException(
        'Choose product features; non-fiscal close is a Venue-only policy',
      );
    const keys = [...new Set(body.featureKeys as string[])];
    return this.db.$transaction(async (tx) => {
      const features = await tx.feature.findMany({
        where: { key: { in: keys } },
      });
      if (features.length !== keys.length)
        throw new BadRequestException('Unknown feature');
      const before = id
        ? await tx.plan.findUniqueOrThrow({
            where: { id },
            include: { features: true },
          })
        : null;
      const data = {
        key,
        name,
        description,
        priceMinor,
        currency,
        billingPeriod: String(body.billingPeriod),
        status: body.status as 'ACTIVE' | 'RETIRED',
        mediaQuotaBytes,
        mediaQuotaFiles,
      };
      const plan = id
        ? await tx.plan.update({ where: { id }, data })
        : await tx.plan.create({ data });
      await tx.planFeature.deleteMany({ where: { planId: plan.id } });
      await tx.planFeature.createMany({
        data: features.map((f) => ({ planId: plan.id, featureId: f.id })),
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: id ? 'plan.updated' : 'plan.created',
          targetType: 'Plan',
          targetId: plan.id,
          metadata: {
            from: before ? JSON.parse(JSON.stringify(before)) : null,
            to: { ...data, featureKeys: keys },
          },
        },
      });
      return plan;
    });
  }
}
