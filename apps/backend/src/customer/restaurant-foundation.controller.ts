import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  HttpCode,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { EdgeDevice } from '../edge/edge-device-context';
import type { EdgeDeviceContext } from '../edge/edge-device-context';
import { RestaurantFoundationService } from './restaurant-foundation.service';
import { MenuCatalogService } from '../menu-catalog/menu-catalog.service';
import { MenuClientGuard } from '../menu-catalog/menu-client.guard';

@Controller('customer/venues/:venueId/catalog')
@UseGuards(CustomerGuard)
export class CustomerCatalogController {
  constructor(private readonly foundation: RestaurantFoundationService) {}
  @Get()
  @Header('Cache-Control', 'private, no-store')
  read(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    return this.foundation.read(actor, id);
  }
  @Get('retired')
  @Header('Cache-Control', 'private, no-store')
  retired(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    return this.foundation.retired(actor, id);
  }
  @Post('mutations')
  @HttpCode(200)
  mutate(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: unknown,
  ) {
    return this.foundation.mutate(actor, id, body);
  }
}
@Controller('edge/restaurant-foundation')
@UseGuards(EdgeDeviceGuard, MenuClientGuard)
export class DeviceFoundationController {
  constructor(private readonly foundation: RestaurantFoundationService) {}
  @Post('bootstrap')
  @Header('Cache-Control', 'private, no-store')
  bootstrap(@EdgeDevice() actor: EdgeDeviceContext) {
    return this.foundation.bootstrap(actor.venueId, actor.deviceId);
  }
}

/**
 * Canonical Menu for enrolled POS Devices: Device -> Venue only, any ACTIVE
 * Device of the Venue (no primary requirement). The POS commits locally first
 * and calls these asynchronously; they never gate local operation.
 */
@Controller('edge/menu')
@UseGuards(EdgeDeviceGuard, MenuClientGuard)
export class DeviceMenuController {
  constructor(private readonly catalogs: MenuCatalogService) {}
  @Get('catalog')
  @Header('Cache-Control', 'private, no-store')
  catalog(@EdgeDevice() actor: EdgeDeviceContext) {
    return this.catalogs.snapshot(actor.venueId);
  }
  @Get('retired')
  @Header('Cache-Control', 'private, no-store')
  retired(@EdgeDevice() actor: EdgeDeviceContext) {
    return this.catalogs.retired(actor.venueId);
  }
  @Get('changes')
  @Header('Cache-Control', 'private, no-store')
  changes(
    @EdgeDevice() actor: EdgeDeviceContext,
    @Query('since') since: string,
  ) {
    return this.catalogs.changes(actor.venueId, Number(since));
  }
  @Post('mutations')
  @HttpCode(200)
  mutate(@EdgeDevice() actor: EdgeDeviceContext, @Body() body: unknown) {
    return this.catalogs.apply(
      actor.venueId,
      { type: 'DEVICE', id: actor.deviceId, source: 'POS' },
      body,
    );
  }
}
