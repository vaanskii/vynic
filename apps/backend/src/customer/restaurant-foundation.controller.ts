import {
  Body,
  Controller,
  Get,
  Header,
  Param,
  Post,
  Put,
  UseGuards,
} from '@nestjs/common';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { EdgeDeviceGuard } from '../edge/edge-device.guard';
import { EdgeDevice } from '../edge/edge-device-context';
import type { EdgeDeviceContext } from '../edge/edge-device-context';
import { RestaurantFoundationService } from './restaurant-foundation.service';

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
  @Put(':kind')
  save(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Param('kind') kind: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.foundation.save(actor, id, kind, body);
  }
}
@Controller('edge/restaurant-foundation')
@UseGuards(EdgeDeviceGuard)
export class DeviceFoundationController {
  constructor(private readonly foundation: RestaurantFoundationService) {}
  @Post('bootstrap')
  @Header('Cache-Control', 'private, no-store')
  bootstrap(@EdgeDevice() actor: EdgeDeviceContext) {
    return this.foundation.bootstrap(actor.venueId, actor.deviceId);
  }
}
