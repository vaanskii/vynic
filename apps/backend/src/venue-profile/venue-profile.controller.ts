import { Body, Controller, Get, Put, UseGuards } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { StaffRole } from '../staff/staff-role';
import {
  ManagerAuth,
  type ManagerAuthContext,
} from '../auth/manager-auth-context';
import { FeatureGuard } from '../entitlements/feature.guard';
import { RequiresFeature } from '../entitlements/requires-feature.decorator';
import { FeatureKeys } from '../entitlements/feature-keys';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import {
  EdgeDevice,
  type EdgeDeviceContext,
} from '../edge/edge-device-context';
import { profileSelect, saveProfile } from './venue-profile';

@Controller('mobile/venue-profile')
@UseGuards(JwtAuthGuard, RolesGuard, FeatureGuard)
@Roles(StaffRole.MANAGER)
@RequiresFeature(FeatureKeys.MANAGER_APP)
export class ManagerVenueProfileController {
  constructor(private readonly db: PrismaService) {}
  @Get() get(@ManagerAuth() actor: ManagerAuthContext) {
    return this.db.venue.findUniqueOrThrow({
      where: { id: actor.venueId },
      select: profileSelect,
    });
  }
  @Put() save(
    @ManagerAuth() actor: ManagerAuthContext,
    @Body() body: Record<string, unknown>,
  ) {
    return saveProfile(this.db, actor.venueId, body, {
      id: actor.staffId,
      source: 'MANAGER',
    });
  }
}
@Controller('edge/venue-profile')
@UseGuards(EdgeDeviceGuard)
export class DeviceVenueProfileController {
  constructor(private readonly db: PrismaService) {}
  @Put() save(
    @EdgeDevice() actor: EdgeDeviceContext,
    @Body() body: Record<string, unknown>,
  ) {
    return saveProfile(this.db, actor.venueId, body, {
      id: actor.deviceId,
      source: 'POS',
    });
  }
}
