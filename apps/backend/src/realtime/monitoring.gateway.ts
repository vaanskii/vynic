import { ManagerTenantService } from '../auth/manager-tenant.service';
import type { TenantContext } from '../tenancy/tenant-context';
import { Inject, forwardRef, Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayInit,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { PresenceService } from './presence.service';
import { HybridNotificationService } from './notifications/hybrid-notification.service';
import type { BroadcastOptions, WsEvent, WsEventType } from './ws-events';

export type { WsEventType, WsEvent, BroadcastOptions } from './ws-events';

/**
 * Socket.IO CORS check. Native clients (mobile app) send no Origin header and
 * are always allowed; browser origins must be in FRONTEND_URL / ALLOWED_ORIGINS.
 * (CORS is defense-in-depth here — the JWT handshake is the real gate.)
 */
function isAllowedSocketOrigin(
  origin: string | undefined,
  cb: (err: Error | null, allow?: boolean) => void,
): void {
  if (!origin) return cb(null, true);
  const allowed = [
    process.env.FRONTEND_URL,
    ...(process.env.ALLOWED_ORIGINS?.split(',') ?? []),
  ]
    .map((o) => o?.trim())
    .filter((o): o is string => Boolean(o));
  cb(null, allowed.includes(origin));
}

@WebSocketGateway({
  cors: { origin: isAllowedSocketOrigin },
  pingTimeout: 20000,
  pingInterval: 25000,
})
export class MonitoringGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server!: Server;

  constructor(
    private readonly jwtService: JwtService,
    private readonly presence: PresenceService,
    private readonly managerTenant: ManagerTenantService,
    @Inject(forwardRef(() => HybridNotificationService))
    private readonly hybrid: HybridNotificationService,
  ) {}

  afterInit(server: Server) {
    console.log('[WS] Monitoring Gateway initialised');

    server.use(async (socket, next) => {
      try {
        const auth = socket.handshake.auth as
          | Record<string, unknown>
          | undefined;
        let token = typeof auth?.token === 'string' ? auth.token : undefined;
        if (!token) {
          const h = socket.handshake.headers.authorization;
          if (typeof h === 'string' && h.startsWith('Bearer ')) {
            token = h.slice(7);
          }
        }
        if (!token || token.length < 10) {
          // Reject: only authenticated managers may subscribe to live data.
          return next(new Error('unauthorized'));
        }
        const decoded = await this.jwtService.verifyAsync<{
          sub: string;
          exp: number;
        }>(token);
        const principal = await this.managerTenant.resolveByStaffId(
          decoded.sub,
          true,
        );
        if (!principal || !Number.isFinite(decoded.exp))
          return next(new Error('unauthorized'));
        socket.data = { ...principal, expiresAt: decoded.exp * 1000 };
        await socket.join(this.managerRoom(principal.venueId));
        this.presence.addSocket(
          principal.venueId,
          principal.username,
          socket.id,
        );
        next();
      } catch {
        next(new Error('unauthorized'));
      }
    });
  }

  handleConnection(client: Socket) {
    console.log(`[WS] Client connected: ${client.id}`);
    client.emit('heartbeat', { ts: new Date().toISOString() });
  }

  handleDisconnect(client: Socket) {
    this.presence.removeSocket(client.id);
    console.log(`[WS] Client disconnected: ${client.id}`);
  }

  broadcastUpdate<T = unknown>(
    tenant: TenantContext,
    type: WsEventType,
    payload: T,
    options?: BroadcastOptions,
  ): void {
    if (!tenant?.venueId) throw new Error('Realtime requires a resolved Venue');
    void this.hybrid
      .deliver(type, payload, { ...options, venueId: tenant.venueId })
      .catch((error: unknown) =>
        new Logger(MonitoringGateway.name).error(
          'Realtime delivery failed',
          error,
        ),
      );
  }

  /**
   * Low-level emit used after hybrid persistence / FCM routing.
   */
  private managerRoom(venueId: string): string {
    if (!venueId) throw new Error('Realtime requires a resolved Venue');
    return `managers:${venueId}`;
  }

  async emitEnvelope<T>(
    event: WsEvent<T>,
    options: BroadcastOptions & { venueId: string },
  ): Promise<void> {
    const room = this.managerRoom(options.venueId);
    // Existing connections cannot retain access after disable, reassignment or expiry.
    for (const socket of await this.server.in(room).fetchSockets()) {
      const principal = await this.managerTenant.resolveByStaffId(
        socket.data.staffId,
        true,
      );
      if (
        !principal ||
        principal.venueId !== options.venueId ||
        principal.username !== socket.data.username ||
        Date.now() >= socket.data.expiresAt
      ) {
        this.presence.removeSocket(socket.id);
        socket.disconnect(true);
      }
    }
    const exclude = (options?.excludeSocketIds ?? [])
      .map((s) => String(s).trim())
      .filter((s) => s.length > 0);

    // Emit only to authenticated managers (room joined on valid JWT), never to
    // every connected socket. `except` drops the socket(s) that originated the
    // change so the acting device isn't echoed.
    const target = exclude.length
      ? this.server.to(room).except(exclude)
      : this.server.to(room);

    target.emit(event.type, event);
    if (event.type !== 'data_updated') {
      target.emit('data_updated', event);
    }
  }

  @SubscribeMessage('ping')
  handlePing(_client: Socket) {
    return { event: 'pong', data: new Date().toISOString() };
  }
}
