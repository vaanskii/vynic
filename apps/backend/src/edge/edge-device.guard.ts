import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { DeviceCredentialService } from '../auth/device-credential.service';
import type { PosAuthenticatedRequest } from '../auth/pos-auth-context';

/**
 * Authenticates an Edge installation for the Cloud → Edge work transport.
 *
 * Device credentials only. PosSyncGuard still accepts the legacy shared key for
 * snapshot pushes, but that key names a Venue and no Device: it cannot say which
 * machine holds a lease, so it cannot be allowed to claim or acknowledge work.
 * Refusing it here is what keeps the queue's ownership rules meaningful.
 *
 * The credential arrives in the same `X-POS-Sync-Key` header the POS already
 * sends, so an Edge client needs no second secret channel.
 *
 * Deliberately not entitlement-gated. This is infrastructure: no commercial
 * feature may switch a restaurant's transport off.
 */
@Injectable()
export class EdgeDeviceGuard implements CanActivate {
  constructor(private readonly deviceCredentials: DeviceCredentialService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest<PosAuthenticatedRequest>();
    const raw =
      request.headers['x-pos-sync-key'] ?? request.headers['X-POS-Sync-Key'];
    const provided = (Array.isArray(raw) ? raw[0] : raw)?.trim();

    if (!this.deviceCredentials.isDeviceCredential(provided)) {
      throw new UnauthorizedException(
        'Edge transport requires a device credential',
      );
    }

    // Verification also rejects a revoked Device and a disabled Venue, and
    // refreshes Device.lastSeenAt — so a poll is the connectivity signal.
    const auth = await this.deviceCredentials.verifyCredential(provided ?? '');
    if (!auth?.deviceId) {
      throw new UnauthorizedException('Invalid or revoked device credential');
    }

    request.posAuthContext = auth;
    return true;
  }
}
