import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PlatformAuditModule } from '../platform/platform-audit.module';
import { DeviceEnrollmentController } from './device-enrollment.controller';
import { DeviceEnrollmentService } from './device-enrollment.service';
import { EdgeCommandService } from './edge-command.service';
import { EdgeDeviceGuard } from './edge-device.guard';
import { EdgeTransportController } from './edge-transport.controller';
import { EnrollmentRateLimiter } from './enrollment-rate-limiter';

/**
 * Cloud ↔ Edge transport, and how a terminal gets onto it.
 *
 * Separate from the POS sync module on purpose: snapshot ingestion is Edge →
 * Cloud state, this is Cloud → Edge work, and collapsing the two would make it
 * impossible to version or retry them independently.
 *
 * Enrollment lives here rather than in the control plane because the request
 * comes from the Edge, unauthenticated, on the same base path as the transport
 * it is asking to join. The control plane imports this module to mint and list
 * invitations; the reverse import would be a cycle.
 */
@Module({
  imports: [AuthModule, PlatformAuditModule],
  controllers: [EdgeTransportController, DeviceEnrollmentController],
  providers: [
    EdgeCommandService,
    EdgeDeviceGuard,
    DeviceEnrollmentService,
    EnrollmentRateLimiter,
  ],
  exports: [EdgeCommandService, DeviceEnrollmentService],
})
export class EdgeTransportModule {}
