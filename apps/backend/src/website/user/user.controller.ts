import {
  Controller,
  Get,
  Patch,
  Body,
  UseGuards,
  Request,
} from '@nestjs/common';
import { WebsiteAuthGuard } from '../auth/website-auth.guard';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import type { TenantContext } from '../../tenancy/tenant-context';
import { WebsiteTenant } from '../tenancy/website-tenant-context';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { UserService } from './user.service';

interface RequestWithUser extends Request {
  user: { id: string; email: string };
}

@Controller('api/user')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @UseGuards(WebsiteAuthGuard)
  @Get('profile')
  async getProfile(@Request() req: RequestWithUser) {
    return this.userService.getProfile(req.user.id);
  }

  /**
   * The customer's bookings at this restaurant. The account is global; the
   * bookings shown are the ones belonging to the Venue whose site this is.
   */
  @UseGuards(WebsiteAuthGuard, WebsiteTenantGuard, FeatureGuard)
  @RequiresFeature(FeatureKeys.WEBSITE)
  @Get('reservations')
  async getUserReservations(
    @WebsiteTenant() tenant: TenantContext,
    @Request() req: RequestWithUser,
  ) {
    return this.userService.getUserReservations(tenant, req.user.id);
  }

  @UseGuards(WebsiteAuthGuard)
  @Patch('profile')
  async updateProfile(
    @Request() req: RequestWithUser,
    @Body() dto: { firstName: string; lastName: string },
  ) {
    return this.userService.updateProfile(req.user.id, dto);
  }
}
