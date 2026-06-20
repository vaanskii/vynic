import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';

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

  canActivate(context: ExecutionContext): boolean {
    const expected = process.env.POS_SYNC_API_KEY?.trim();
    const req = context.switchToHttp().getRequest<{
      headers: Record<string, string | string[] | undefined>;
    }>();
    const raw =
      req.headers['x-pos-sync-key'] ?? req.headers['X-POS-Sync-Key'];
    const provided = (Array.isArray(raw) ? raw[0] : raw)?.trim();

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
      return true;
    }

    if (!provided || provided !== expected) {
      throw new UnauthorizedException('Invalid or missing POS sync API key');
    }
    return true;
  }
}
