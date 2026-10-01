import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { CustomerActor, CustomerGuard } from '../customer/customer-auth';
import type { CustomerPrincipal } from '../customer/customer-auth';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { EdgeDevice } from '../edge/edge-device-context';
import type { EdgeDeviceContext } from '../edge/edge-device-context';
import { requireMenuClient } from './menu-client-policy';
import { MenuRolloutService } from './menu-rollout.service';

@Controller('edge/menu-client')
@UseGuards(EdgeDeviceGuard)
export class DeviceMenuClientController {
  constructor(private readonly db: PrismaService) {}
  @Post('check-in')
  async checkIn(
    @EdgeDevice() actor: EdgeDeviceContext,
    @Body() body: Record<string, unknown>,
  ) {
    if (
      !body ||
      Object.keys(body).some((key) => key !== 'menuClient') ||
      !('menuClient' in body)
    )
      throw new BadRequestException(
        'Only this authenticated Device may report menuClient',
      );
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM pos."Venue" WHERE id=${actor.venueId} FOR UPDATE`;
      return requireMenuClient(
        tx,
        actor.venueId,
        actor.deviceId,
        body.menuClient,
        false,
      );
    });
  }
}

@Controller('customer/venues/:venueId/menu-rollout')
@UseGuards(CustomerGuard)
export class CustomerMenuRolloutController {
  constructor(private readonly rollout: MenuRolloutService) {}
  @Get()
  @Header('Cache-Control', 'private, no-store')
  readiness(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') venueId: string,
  ) {
    return this.rollout.readiness(actor, venueId);
  }
  @Post('cutover')
  cutover(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') venueId: string,
    @Body() body: unknown,
  ) {
    return this.rollout.cutover(actor, venueId, body);
  }
  @Post('rollback')
  rollback(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') venueId: string,
  ) {
    return this.rollout.rollback(actor, venueId);
  }
}
