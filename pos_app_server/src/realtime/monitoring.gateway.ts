import { Inject, forwardRef } from '@nestjs/common';
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

@WebSocketGateway({
  cors: { origin: '*' },
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
    @Inject(forwardRef(() => HybridNotificationService))
    private readonly hybrid: HybridNotificationService,
  ) {}

  afterInit(server: Server) {
    console.log('[WS] Monitoring Gateway initialised');

    server.use(async (socket, next) => {
      try {
        const auth = socket.handshake.auth as Record<string, unknown> | undefined;
        let token =
          typeof auth?.token === 'string' ? (auth.token as string) : undefined;
        if (!token) {
          const h = socket.handshake.headers.authorization;
          if (typeof h === 'string' && h.startsWith('Bearer ')) {
            token = h.slice(7);
          }
        }
        if (!token || token.length < 10) {
          return next();
        }
        const decoded = await this.jwtService.verifyAsync<{
          username: string;
          role: string;
        }>(token);
        socket.data.username = decoded.username;
        socket.data.role = decoded.role;
        socket.join('managers');
        this.presence.addSocket(decoded.username, socket.id);
        next();
      } catch {
        next();
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
    type: WsEventType,
    payload: T,
    options?: BroadcastOptions,
  ): void {
    void this.hybrid.deliver(type, payload as unknown, options);
  }

  /**
   * Low-level emit used after hybrid persistence / FCM routing.
   */
  emitEnvelope<T>(event: WsEvent<T>, options?: BroadcastOptions): void {
    const exclude = new Set(
      (options?.excludeSocketIds ?? [])
        .map((s) => String(s).trim())
        .filter((s) => s.length > 0),
    );

    const emitPairToSocket = (socket: Socket) => {
      socket.emit(event.type, event);
      if (event.type !== 'data_updated') {
        socket.emit('data_updated', event);
      }
    };

    if (exclude.size === 0) {
      this.server.emit(event.type, event);
      if (event.type !== 'data_updated') {
        this.server.emit('data_updated', event);
      }
      return;
    }

    this.server.sockets.sockets.forEach((socket) => {
      if (exclude.has(socket.id)) return;
      emitPairToSocket(socket);
    });
  }

  @SubscribeMessage('ping')
  handlePing(_client: Socket) {
    return { event: 'pong', data: new Date().toISOString() };
  }
}
