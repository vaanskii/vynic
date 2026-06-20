import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
} from '@nestjs/common';
import { Request } from 'express';
import { CryptoService } from '../common/crypto.service';
import { WebsiteAuthService } from './auth.service';

@Injectable()
export class WebsiteAuthGuard implements CanActivate {
  constructor(
    private readonly cryptoService: CryptoService,
    private readonly authService: WebsiteAuthService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const encryptedAccessToken = request.cookies['access_token'];

    if (!encryptedAccessToken) {
      throw new UnauthorizedException('Access token not found');
    }

    try {
      const accessToken = this.cryptoService.decrypt(encryptedAccessToken);
      const user = await this.authService.verifyToken(accessToken);
      (request as Request & { user: unknown }).user = user;
      return true;
    } catch {
      throw new UnauthorizedException('Invalid access token');
    }
  }
}
