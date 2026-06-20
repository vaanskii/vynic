import { Global, Module } from '@nestjs/common';
import { PosCallbackClient } from './pos-callback.client';

/**
 * Provides the POS-callback transport as a single app-wide singleton.
 *
 * Global so every module (SyncController, PosOutboxService, the website
 * reservation bridge, …) injects the same instance — the one whose callback
 * URL / connection key SyncController populates from the POS handshake.
 */
@Global()
@Module({
  providers: [PosCallbackClient],
  exports: [PosCallbackClient],
})
export class PosCallbackModule {}
