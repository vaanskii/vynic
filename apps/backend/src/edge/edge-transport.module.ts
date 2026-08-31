import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { EdgeCommandService } from './edge-command.service';
import { EdgeDeviceGuard } from './edge-device.guard';
import { EdgeTransportController } from './edge-transport.controller';

/**
 * Cloud ↔ Edge transport.
 *
 * Separate from the POS sync module on purpose: snapshot ingestion is Edge →
 * Cloud state, this is Cloud → Edge work, and collapsing the two would make it
 * impossible to version or retry them independently.
 */
@Module({
  imports: [AuthModule],
  controllers: [EdgeTransportController],
  providers: [EdgeCommandService, EdgeDeviceGuard],
  exports: [EdgeCommandService],
})
export class EdgeTransportModule {}
