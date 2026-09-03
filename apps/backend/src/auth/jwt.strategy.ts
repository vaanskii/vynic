import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { requireEnv } from '../shared/require-env';
import type { ManagerRequestUser } from './manager-auth-context';
import { ManagerTenantService } from './manager-tenant.service';

export interface JwtPayload {
  sub: string;
  username: string;
  role: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly managerTenant: ManagerTenantService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: requireEnv('JWT_SECRET'),
    });
  }

  /**
   * Called after signature verification. Return value is injected as `req.user`.
   *
   * Only the subject is taken from the token. Venue, Organization, role, and
   * activity are re-resolved from the Staff row, so the tenant on a request is
   * always the one the server currently owns — never a claim minted up to 24
   * hours earlier. The token's own `username`/`role` are deliberately ignored.
   */
  async validate(payload: JwtPayload): Promise<ManagerRequestUser> {
    const manager = await this.managerTenant.resolveByStaffId(payload.sub);
    if (!manager) {
      throw new UnauthorizedException('Manager identity is no longer valid');
    }
    return { userId: manager.staffId, ...manager };
  }
}
