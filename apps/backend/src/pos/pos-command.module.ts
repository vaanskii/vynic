import { Global, Module } from '@nestjs/common';
import { EdgeTransportModule } from '../edge/edge-transport.module';
import { PosCommandDispatcher } from './pos-command-dispatcher.service';
import { PosOutboxService } from './pos-outbox.service';
import { PosReservationMirrorService } from './pos-reservation-mirror.service';

/**
 * How Cloud reaches a restaurant's POS, and how it reads what the POS holds.
 *
 * Global, for the same reason `PosCallbackModule` is: the Manager services, the
 * website reservation bridge and the snapshot ingestion all need these, they
 * live in three different modules, and there must be exactly one outbox worker
 * rather than one per importer.
 *
 * `PosOutboxService` moved here from `AppModule` so the dispatcher and its
 * fallback are provided together. It is the same single instance, still injected
 * into snapshot ingestion through the existing forward reference.
 */
@Global()
@Module({
  imports: [EdgeTransportModule],
  providers: [
    PosOutboxService,
    PosCommandDispatcher,
    PosReservationMirrorService,
  ],
  exports: [
    PosOutboxService,
    PosCommandDispatcher,
    PosReservationMirrorService,
  ],
})
export class PosCommandModule {}
