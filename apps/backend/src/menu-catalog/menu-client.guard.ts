import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import type { PosAuthenticatedRequest } from '../auth/pos-auth-context';
import { MENU_CLIENT_HEADER, requireMenuClient } from './menu-client-policy';

@Injectable()
export class MenuClientGuard implements CanActivate {
  constructor(private readonly db: PrismaService) {}
  async canActivate(context: ExecutionContext) {
    const request = context
      .switchToHttp()
      .getRequest<PosAuthenticatedRequest>();
    const auth = request.posAuthContext;
    if (!auth?.deviceId)
      throw new Error('Device authentication must precede Menu admission');
    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM pos."Venue" WHERE id=${auth.venueId} FOR UPDATE`;
      await requireMenuClient(
        tx,
        auth.venueId,
        auth.deviceId,
        request.headers[MENU_CLIENT_HEADER],
      );
    });
    return true;
  }
}
