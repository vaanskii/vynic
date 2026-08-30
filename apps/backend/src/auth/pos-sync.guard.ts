import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { timingSafeEqual } from 'node:crypto';
import { DeviceCredentialService } from './device-credential.service';
import { PosAuthenticatedRequest } from './pos-auth-context';

/**
 * Protects POS → cloud push endpoints (`POST /sync/manager-data`, etc.).
 * Set POS_SYNC_API_KEY in the server environment; Windows POS sends X-POS-Sync-Key.
 *
 * Fails closed in production: if POS_SYNC_API_KEY is unset, requests are denied.
 * In non-production, an unset key is allowed (dev only) with a one-time warning.
 */
@Injectable()
export class PosSyncGuard implements CanActivate {
  private static warnedMissingKey = false;

  constructor(private readonly deviceCredentials: DeviceCredentialService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const expected = process.env.POS_SYNC_API_KEY?.trim();
    const req = context.switchToHttp().getRequest<PosAuthenticatedRequest>();
    const raw = req.headers['x-pos-sync-key'] ?? req.headers['X-POS-Sync-Key'];
    const provided = (Array.isArray(raw) ? raw[0] : raw)?.trim();

    if (this.deviceCredentials.isDeviceCredential(provided)) {
      const deviceContext = await this.deviceCredentials.verifyCredential(
        provided ?? '',
      );
      if (!deviceContext) {
        throw new UnauthorizedException('Invalid POS device credential');
      }
      req.posAuthContext = deviceContext;
      return true;
    }

    if (!expected) {
      // Fail closed in production — never leave POS push endpoints open.
      if (process.env.NODE_ENV === 'production') {
        throw new UnauthorizedException(
          'POS sync API key is not configured on the server',
        );
      }
      if (!PosSyncGuard.warnedMissingKey) {
        console.warn(
          '[Sync] POS_SYNC_API_KEY is not set — POS push endpoints are unauthenticated (dev only).',
        );
        PosSyncGuard.warnedMissingKey = true;
      }
      req.posAuthContext = {
        authenticationMode: 'legacy_shared_key',
        deviceId: null,
      };
      return true;
    }

    if (!provided || !this.matchesLegacyKey(provided, expected)) {
      throw new UnauthorizedException('Invalid or missing POS sync API key');
    }
    // Transitional compatibility path. Remove only after every deployed POS
    // has received a Device credential through the future onboarding flow.
    req.posAuthContext = {
      authenticationMode: 'legacy_shared_key',
      deviceId: null,
    };
    return true;
  }

  private matchesLegacyKey(provided: string, expected: string): boolean {
    const providedBytes = Buffer.from(provided);
    const expectedBytes = Buffer.from(expected);
    return (
      providedBytes.length === expectedBytes.length &&
      timingSafeEqual(providedBytes, expectedBytes)
    );
  }
}
