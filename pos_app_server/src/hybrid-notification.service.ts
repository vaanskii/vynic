import {
  forwardRef,
  Inject,
  Injectable,
  Logger,
} from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';
import { PrismaService } from './prisma.service';
import { PresenceService } from './presence.service';
import { MonitoringGateway } from './monitoring.gateway';
import { buildManagerPushCopy } from './manager-notification-push.mapper';
import type { BroadcastOptions, WsEvent, WsEventType } from './ws-events';

@Injectable()
export class HybridNotificationService {
  private readonly logger = new Logger(HybridNotificationService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly presence: PresenceService,
    @Inject(forwardRef(() => MonitoringGateway))
    private readonly gateway: MonitoringGateway,
  ) {}

  /**
   * Persist when applicable, then always emit Socket.IO envelope.
   */
  async deliver(
    type: WsEventType,
    payload: unknown,
    options?: BroadcastOptions,
  ): Promise<void> {
    const notificationId = uuidv4();
    const timestamp = new Date().toISOString();
    const envelope: WsEvent & { notificationId: string } = {
      type,
      payload,
      timestamp,
      notificationId,
    };

    const pushCopy = buildManagerPushCopy(type, payload);

    try {
      if (pushCopy) {
        await this.prisma.managerNotification.create({
          data: {
            id: notificationId,
            wsType: type,
            title: pushCopy.title,
            body: pushCopy.body,
            envelope: envelope as object,
          },
        });

        const managers = await this.prisma.staff.findMany({
          where: {
            isActive: true,
            role: { in: ['ADMIN', 'MANAGER'] },
          },
          select: { username: true },
        });

        const online = this.presence.getOnlineStaffUsernames();

        const deliveryRows = managers.map((m) => ({
          notificationId,
          staffUsername: m.username,
          channel: 'SOCKET',
        }));

        if (deliveryRows.length > 0) {
          await this.prisma.managerNotificationDelivery.createMany({
            data: deliveryRows,
            skipDuplicates: true,
          });
        }

        void online; // retained for possible future routing logic
      }
    } catch (e) {
      this.logger.warn(
        `Hybrid notification persistence failed: ${(e as Error).message}`,
      );
    }

    this.gateway.emitEnvelope(envelope, options);
  }
}
