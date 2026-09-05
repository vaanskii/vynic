import { Module } from '@nestjs/common';
import { InventoryService } from './inventory.service';
import { ReceivingService } from './receiving.service';

/**
 * The Inventory domain, shared by the two principals that reach it.
 *
 * The Manager administers it through `Staff -> Venue`; the POS reads a complete
 * projection of it through `Device -> Venue`. Both resolve their own tenant, so
 * the domain services take a resolved Venue and never a client-supplied one.
 */
@Module({
  providers: [InventoryService, ReceivingService],
  exports: [InventoryService, ReceivingService],
})
export class InventoryModule {}
