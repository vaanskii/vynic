import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { FeatureKeys } from '../entitlements/feature-keys';
import { withoutProfitability } from '../entitlements/commercial-projection';
import { SaleConsumptionService } from '../inventory/sale-consumption.service';
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Query,
  Post,
  UseGuards,
} from '@nestjs/common';
import { EDGE_COMMAND_CONTRACT_VERSION } from '../shared/contracts/edge-command';
import { EdgeCommandService } from './edge-command.service';
import { EdgeDevice, type EdgeDeviceContext } from './edge-device-context';
import { EdgeDeviceGuard } from './edge-device.guard';
import { InventoryService } from '../inventory/inventory.service';

interface ClaimBody {
  limit?: number;
  acceptedContractVersions?: number[];
}

interface AcknowledgeBody {
  commandId?: string;
  status?: string;
  code?: string | null;
  detail?: string | null;
}

/**
 * The Edge side of Cloud ↔ Edge transport.
 *
 * Both routes are opened by the restaurant, never by Cloud. That is the whole
 * point: a Cloud deployment cannot reach 192.168.x.x, so work waits here until
 * an Edge with a Device credential comes and asks for it.
 *
 * Neither route accepts a venueId or deviceId. Tenancy comes from the credential
 * the caller authenticated with, and there is no parameter that could widen it.
 */
@Controller('edge')
@UseGuards(EdgeDeviceGuard)
export class EdgeTransportController {
  constructor(
    private readonly entitlements: VenueEntitlementsService,
    private readonly commands: EdgeCommandService,
    private readonly inventory: InventoryService,
    private readonly consumption: SaleConsumptionService,
  ) {}

  /**
   * Complete Cloud-authoritative Inventory projection for this Device's Venue.
   * The Device cannot name a Venue; EdgeDeviceGuard derived it from the
   * credential before this method runs.
   */
  @Post('inventory/consumption')
  consume(@EdgeDevice() device: EdgeDeviceContext, @Body() body: unknown) {
    return this.consumption.applyFromDevice(device, body);
  }

  @Get('inventory/catalog')
  async inventoryCatalog(
    @EdgeDevice() device: EdgeDeviceContext,
    @Query('version') version?: string,
  ) {
    const features = await this.entitlements.effectiveFeatures(device.venueId);
    if (!features.includes(FeatureKeys.INVENTORY))
      return {
        version: version === '5' ? 5 : version === '4' ? 4 : 3,
        generatedAt: new Date().toISOString(),
        features,
        stockItems: [],
        suppliers: [],
        recipes: [],
      };
    const catalog = await this.inventory.getCatalog(
      device,
      version === '5' ? 5 : version === '4' ? 4 : 3,
    );
    return {
      ...(features.includes(FeatureKeys.PROFITABILITY)
        ? catalog
        : withoutProfitability(catalog)),
      features,
    };
  }

  /** What work is waiting for this Edge, and a lease on each item returned. */
  @Post('commands/claim')
  async claim(
    @EdgeDevice() device: EdgeDeviceContext,
    @Body() body: ClaimBody = {},
  ) {
    const commands = await this.commands.claim(device, {
      limit: body.limit,
      acceptedContractVersions: body.acceptedContractVersions,
    });
    return {
      contractVersion: EDGE_COMMAND_CONTRACT_VERSION,
      commands,
      serverTime: new Date().toISOString(),
    };
  }

  /** What happened to one command. Safe to repeat. */
  @Post('commands/ack')
  async acknowledge(
    @EdgeDevice() device: EdgeDeviceContext,
    @Body() body: AcknowledgeBody,
  ) {
    const commandId = body.commandId?.trim();
    if (!commandId) {
      throw new BadRequestException('commandId is required');
    }
    if (body.status !== 'SUCCEEDED' && body.status !== 'FAILED') {
      throw new BadRequestException('status must be SUCCEEDED or FAILED');
    }

    const result = await this.commands.acknowledge(device, {
      commandId,
      status: body.status,
      code: body.code ?? null,
      detail: body.detail ?? null,
    });
    return { contractVersion: EDGE_COMMAND_CONTRACT_VERSION, ...result };
  }
}
