import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { PlatformAuthenticatedRequest } from './platform-auth-context';
import { PlatformAuthService } from './platform-auth.service';

interface BearerRequest extends PlatformAuthenticatedRequest {
  headers: Record<string, string | string[] | undefined>;
}

/**
 * Admits only authenticated Vynic administrators.
 *
 * Every control-plane route carries this. There are no unauthenticated
 * convenience endpoints in the platform module: the whole point of Step 7A is
 * that these mutations finally have an authorization boundary, and one route
 * without it would be the hole the boundary exists to close.
 */
@Injectable()
export class PlatformAuthGuard implements CanActivate {
  constructor(private readonly auth: PlatformAuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<BearerRequest>();
    const raw = request.headers['authorization'];
    const header = Array.isArray(raw) ? raw[0] : raw;

    const token = header?.startsWith('Bearer ')
      ? header.slice('Bearer '.length).trim()
      : null;
    if (!token) {
      throw new UnauthorizedException('Platform authentication required');
    }

    const principal = await this.auth.resolve(token);
    if (!principal) {
      throw new UnauthorizedException('Platform authentication required');
    }

    request.platformPrincipal = principal;
    return true;
  }
}
