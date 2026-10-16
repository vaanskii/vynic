import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { PosAuth, type PosAuthContext } from '../auth/pos-auth-context';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import {
  PlatformActor,
  type PlatformPrincipal,
} from '../platform/platform-auth-context';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import { PrinterProvisioningService } from './service';

@Controller('edge/printer-provisioning')
@UseGuards(EdgeDeviceGuard)
export class PrinterEnrollmentController {
  constructor(private readonly service: PrinterProvisioningService) {}
  @Post('enroll')
  enroll(@PosAuth() auth: PosAuthContext, @Body() input: unknown) {
    return this.service.enroll(auth, input);
  }
}
@Controller('platform/venues/:venueId/printer-provisioning')
@UseGuards(PlatformAuthGuard)
export class PrinterConfigurationController {
  constructor(private readonly service: PrinterProvisioningService) {}
  @Get()
  inventory(@Param('venueId') venue: string) {
    return this.service.inventory(venue);
  }
  @Post('configuration')
  publish(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venue: string,
    @Body() input: unknown,
  ) {
    return this.service.publish(actor, venue, input);
  }
  @Post('installations/:installationId/revoke')
  revoke(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('venueId') venue: string,
    @Param('installationId') installation: string,
  ) {
    return this.service.revoke(actor, venue, installation);
  }
}
