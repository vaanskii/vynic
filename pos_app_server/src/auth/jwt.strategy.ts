import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { requireEnv } from '../shared/require-env';

export interface JwtPayload {
  sub: string;
  username: string;
  role: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor() {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: requireEnv('JWT_SECRET'),
    });
  }

  /** Called after signature verification. Return value is injected as `req.user`. */
  async validate(
    payload: JwtPayload,
  ): Promise<{ userId: string; username: string; role: string }> {
    return {
      userId: payload.sub,
      username: payload.username,
      role: payload.role,
    };
  }
}
