import { profileSelect } from '../venue-profile/venue-profile';
import { FeatureKeys } from '../entitlements/feature-keys';
import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Put,
  Req,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { CustomerAuth, CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { CustomerService } from './customer.service';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import { PlatformActor } from '../platform/platform-auth-context';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import { PrismaService } from '../prisma.service';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { EdgeDevice } from '../edge/edge-device-context';
import type { EdgeDeviceContext } from '../edge/edge-device-context';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';

@Controller('customer/auth')
export class CustomerAuthController {
  constructor(private readonly auth: CustomerAuth) {}
  @Post('signup') signup(
    @Body() body: Record<string, unknown>,
    @Req() req: { ip: string },
  ) {
    return this.auth.authenticate(body, req.ip, true);
  }
  @Post('login') login(
    @Body() body: Record<string, unknown>,
    @Req() req: { ip: string },
  ) {
    return this.auth.authenticate(body, req.ip, false);
  }
}
@Controller('customer')
@UseGuards(CustomerGuard)
export class CustomerController {
  constructor(private readonly service: CustomerService) {}
  @Get('portal') portal(@CustomerActor() actor: CustomerPrincipal) {
    return this.service.portal(actor);
  }
  @Post('venues') create(
    @CustomerActor() actor: CustomerPrincipal,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.createVenue(actor, body);
  }
  @Get('venues/:venueId') async status(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    await this.service.venue(actor, id);
    return this.service.status(id);
  }
  @Put('venues/:venueId/profile') profile(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.profile(actor, id, body);
  }
  @Post('venues/:venueId/managers') manager(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.manager(actor, id, 'create', body);
  }
  @Post('venues/:venueId/managers/:staffId/reset') reset(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Param('staffId') staffId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.manager(actor, id, 'reset', body, staffId);
  }
  @Post('venues/:venueId/managers/:staffId/disable') disable(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Param('staffId') staffId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.manager(actor, id, 'disable', body, staffId);
  }
  @Post('venues/:venueId/enrollments') enrollment(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    return this.service.enrollment(actor, id);
  }
  @Post('venues/:venueId/enrollments/:enrollmentId/cancel') cancel(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Param('enrollmentId') enrollmentId: string,
  ) {
    return this.service.cancel(actor, id, enrollmentId);
  }
  @Put('venues/:venueId/devices/:deviceId/printers') async printers(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Param('deviceId') deviceId: string,
    @Body() body: Record<string, unknown>,
  ) {
    await this.service.venue(actor, id);
    return this.service.printers(actor, id, deviceId, body);
  }
}
@Controller('platform/onboarding')
@UseGuards(PlatformAuthGuard)
export class PlatformOnboardingController {
  constructor(
    private readonly db: PrismaService,
    private readonly service: CustomerService,
  ) {}
  @Get('policy') policy() {
    return this.db.onboardingPolicy.findUnique({ where: { id: 'default' } });
  }
  @Put('policy') async save(
    @PlatformActor() actor: PlatformPrincipal,
    @Body() body: Record<string, unknown>,
  ) {
    if (
      typeof body.enabled !== 'boolean' ||
      !Number.isInteger(body.trialDays) ||
      Number(body.trialDays) < 1 ||
      Number(body.trialDays) > 90
    )
      throw new BadRequestException('Invalid trial policy');
    const trialPlanId =
      typeof body.trialPlanId === 'string' ? body.trialPlanId : null;
    if (body.enabled && !trialPlanId)
      throw new BadRequestException('Choose a trial plan');
    if (
      trialPlanId &&
      !(await this.db.plan.findFirst({
        where: { id: trialPlanId, status: 'ACTIVE' },
      }))
    )
      throw new BadRequestException('Active plan required');
    if (body.enabled && trialPlanId) {
      const features = await this.db.planFeature.findMany({
        where: { planId: trialPlanId },
        include: { feature: true },
      });
      const keys = features.map((f) => f.feature.key);
      if (
        !keys.includes(FeatureKeys.POS) ||
        !keys.includes(FeatureKeys.MANAGER_APP)
      )
        throw new BadRequestException(
          'Onboarding trial must include POS and Manager',
        );
    }
    const releaseLinks: Record<string, string> = {};
    for (const [key, value] of Object.entries(
      (body.releaseLinks ?? {}) as object,
    )) {
      if (
        ![
          'posWindows',
          'managerWindows',
          'managerMacos',
          'managerAndroid',
          'managerIos',
        ].includes(key) ||
        typeof value !== 'string'
      )
        throw new BadRequestException('Invalid release link');
      if (!value) continue;
      try {
        const u = new URL(value);
        if (u.protocol !== 'https:' || u.username || u.password)
          throw new Error();
      } catch {
        throw new BadRequestException('Release links must use HTTPS');
      }
      releaseLinks[key] = value;
    }
    return this.db.$transaction(async (tx) => {
      const before = await tx.onboardingPolicy.findUnique({
        where: { id: 'default' },
      });
      const data = {
        enabled: body.enabled as boolean,
        trialDays: Number(body.trialDays),
        trialPlanId,
        releaseLinks,
      };
      const after = await tx.onboardingPolicy.upsert({
        where: { id: 'default' },
        create: data,
        update: data,
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'onboarding.policy_changed',
          targetType: 'OnboardingPolicy',
          targetId: 'default',
          metadata: {
            from: before ? JSON.parse(JSON.stringify(before)) : null,
            to: data,
          },
        },
      });
      return after;
    });
  }
  @Get('venues/:venueId') status(@Param('venueId') id: string) {
    return this.service.status(id);
  }
  @Put('venues/:venueId/devices/:deviceId/printers') printers(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') id: string,
    @Param('deviceId') deviceId: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.printers(actor, id, deviceId, body);
  }
}
@Controller('edge/runtime-config')
@UseGuards(EdgeDeviceGuard)
export class DeviceRuntimeConfigController {
  constructor(
    private readonly db: PrismaService,
    private readonly entitlements: VenueEntitlementsService,
  ) {}
  @Get() async config(@EdgeDevice() actor: EdgeDeviceContext) {
    const device = await this.db.device.findFirstOrThrow({
      where: { id: actor.deviceId, venueId: actor.venueId },
      include: {
        venue: {
          select: { ...profileSelect, timezone: true, currency: true },
        },
      },
    });
    return {
      version: 1,
      venue: device.venue,
      features: await this.entitlements.effectiveFeatures(actor.venueId),
      device: {
        id: device.id,
        displayName: device.displayName,
        runtimeConfig: device.runtimeConfig,
      },
    };
  }
}
