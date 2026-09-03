import { Module } from '@nestjs/common';
import { PlatformAuditService } from './platform-audit.service';

/**
 * The platform audit trail, on its own so two modules can write to it.
 *
 * The control plane records what an administrator did. Device enrollment
 * records what happened to an invitation that administrator created, and it
 * lives in the edge module because the redemption route does. Neither should
 * grow its own audit table, and the alternative — importing the whole
 * PlatformModule into EdgeTransportModule — would be a cycle, since the
 * control plane already imports the edge queue.
 */
@Module({
  providers: [PlatformAuditService],
  exports: [PlatformAuditService],
})
export class PlatformAuditModule {}
