import { Injectable } from '@nestjs/common';
import { randomBytes } from 'crypto';

@Injectable()
export class CsrfService {
  generateToken(): string {
    return randomBytes(32).toString('hex');
  }

  validateToken(sessionToken: unknown, requestToken: unknown): boolean {
    return (
      typeof sessionToken === 'string' &&
      typeof requestToken === 'string' &&
      /^[a-f0-9]{64}$/.test(sessionToken) &&
      sessionToken === requestToken
    );
  }
}
