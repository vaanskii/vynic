import {
  forwardRef,
  Inject,
  Injectable,
  Logger,
} from '@nestjs/common';
import { v4 as uuidv4 } from 'uuid';
import { getApps, initializeApp, applicationDefault } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { PrismaService } from './prisma.service';
import { PresenceService } from './presence.service';
import { MonitoringGateway } from './monitoring.gateway';
import { buildManagerPushCopy } from './manager-notification-push.mapper';
import {
  defaultServiceFeeCoalesceMs,
  getServiceFeeCoalesceKey,
  ServiceFeeNotificationCoalescer,
} from './manager-notification-coalesce';
import type { BroadcastOptions, WsEvent, WsEventType } from './ws-events';

@Injectable()
export class HybridNotificationService {
  private readonly logger = new Logger(HybridNotificationService.name);
  private _fcmInitialized = false;
  private _fcmEnabled = false;
  private readonly serviceFeeCoalescer = new ServiceFeeNotificationCoalescer(
    defaultServiceFeeCoalesceMs,
    (type, payload, options) => this.deliverPersisted(type, payload, options),
  );

  constructor(
    private readonly prisma: PrismaService,
    private readonly presence: PresenceService,
    @Inject(forwardRef(() => MonitoringGateway))
    private readonly gateway: MonitoringGateway,
  ) {}

  /**
   * Persist when applicable, then always emit Socket.IO envelope.
   * Service-fee-only bulk touches defer push/FCM until toggling settles.
   */
  async deliver(
    type: WsEventType,
    payload: unknown,
    options?: BroadcastOptions,
  ): Promise<void> {
    const timestamp = new Date().toISOString();
    const coalesceKey = getServiceFeeCoalesceKey(type, payload);

    if (coalesceKey) {
      this.gateway.emitEnvelope({ type, payload, timestamp }, options);
      this.serviceFeeCoalescer.schedule(coalesceKey, type, payload, options);
      return;
    }

    await this.deliverPersisted(type, payload, options);
  }

  private async deliverPersisted(
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
          channel: online.has(m.username) ? 'SOCKET' : 'FCM',
        }));

        if (deliveryRows.length > 0) {
          await this.prisma.managerNotificationDelivery.createMany({
            data: deliveryRows,
            skipDuplicates: true,
          });
        }
        await this.sendFcmToOfflineManagers({
          notificationId,
          envelope,
          title: pushCopy.title,
          body: pushCopy.body,
          managerUsernames: managers.map((m) => m.username),
          onlineUsernames: online,
        });
      }
    } catch (e) {
      this.logger.warn(
        `Hybrid notification persistence failed: ${(e as Error).message}`,
      );
    }

    this.gateway.emitEnvelope(envelope, options);
  }

  private ensureFcmInitialized(): boolean {
    if (this._fcmInitialized) return this._fcmEnabled;
    this._fcmInitialized = true;
    try {
      if (getApps().length === 0) {
        initializeApp({
          credential: applicationDefault(),
        });
      }
      this._fcmEnabled = true;
      this.logger.log('Firebase Admin Messaging initialized.');
    } catch (error) {
      this._fcmEnabled = false;
      this.logger.warn(
        `FCM disabled (missing credentials): ${(error as Error).message}`,
      );
    }
    return this._fcmEnabled;
  }

  private async sendFcmToOfflineManagers(params: {
    notificationId: string;
    envelope: WsEvent & { notificationId: string };
    title: string;
    body: string;
    managerUsernames: string[];
    onlineUsernames: Set<string>;
  }): Promise<void> {
    if (!this.ensureFcmInitialized()) return;

    const offlineManagers = params.managerUsernames.filter(
      (u) => !params.onlineUsernames.has(u),
    );
    if (offlineManagers.length === 0) return;

    const devices = await this.prisma.pushDevice.findMany({
      where: { staffUsername: { in: offlineManagers } },
      select: { fcmToken: true, staffUsername: true },
    });
    if (devices.length === 0) return;

    const dedupedTokens = Array.from(
      new Set(
        devices
          .map((d) => d.fcmToken?.trim())
          .filter((t): t is string => Boolean(t)),
      ),
    );
    if (dedupedTokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens: dedupedTokens,
      data: {
        title: params.title,
        body: params.body,
        notificationId: params.notificationId,
        envelope: JSON.stringify(params.envelope),
        eventType: params.envelope.type,
        timestamp: params.envelope.timestamp,
      },
      android: {
        priority: 'high',
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    });

    if (response.failureCount > 0) {
      this.logger.warn(
        `FCM send partial failure: ${response.failureCount}/${dedupedTokens.length}`,
      );
      const invalidTokens: string[] = [];
      response.responses.forEach((r, index) => {
        if (r.success) return;
        const code = r.error?.code ?? '';
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token'
        ) {
          invalidTokens.push(dedupedTokens[index]);
        }
      });
      if (invalidTokens.length > 0) {
        await this.prisma.pushDevice.deleteMany({
          where: { fcmToken: { in: invalidTokens } },
        });
      }
    }
  }
}
