import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { readRestaurantServiceFeeSettings } from '../util/mobile-date.util';

/**
 * Device & settings endpoints for the mobile manager app:
 * restaurant settings, missed-notification replay, and push-device
 * registration (`/mobile/restaurant-settings`, `/mobile/notifications`,
 * `/mobile/push/register`, `/mobile/push/unregister`).
 *
 * Extracted verbatim from MobileController; behavior unchanged. The controller
 * keeps the route decorators and passes the authenticated username through.
 */
@Injectable()
export class MobileDevicesService {
  constructor(private readonly prisma: PrismaService) {}

  async getRestaurantSettings() {
    return readRestaurantServiceFeeSettings(this.prisma);
  }

  async getNotifications(username: string, since?: string) {
    let sinceDate: Date;
    if (since && since.trim().length > 0) {
      sinceDate = new Date(since.trim());
      if (Number.isNaN(sinceDate.getTime())) {
        throw new BadRequestException('Invalid since timestamp');
      }
    } else {
      sinceDate = new Date(Date.now() - 24 * 60 * 60 * 1000);
    }

    const rows = await (
      this.prisma as any
    ).managerNotificationDelivery.findMany({
      where: {
        staffUsername: username,
        notification: { createdAt: { gte: sinceDate } },
      },
      include: { notification: true },
      orderBy: { notification: { createdAt: 'asc' } },
      take: 100,
    });

    return rows.map((row: any) => {
      const n = row.notification;
      return {
        id: n.id as string,
        type: n.wsType as string,
        title: n.title as string,
        body: n.body as string,
        envelope: n.envelope,
        createdAt: (n.createdAt as Date).toISOString(),
      };
    });
  }

  async registerPushDevice(
    staffUsername: string,
    payload: { fcmToken?: string; platform?: string },
  ) {
    const fcmToken = (payload.fcmToken ?? '').trim();
    if (!fcmToken) {
      throw new BadRequestException('fcmToken is required');
    }
    await (this.prisma as any).pushDevice.upsert({
      where: { fcmToken },
      update: {
        staffUsername,
        platform: (payload.platform ?? '').trim() || null,
      },
      create: {
        staffUsername,
        fcmToken,
        platform: (payload.platform ?? '').trim() || null,
      },
    });
    return { success: true };
  }

  async unregisterPushDevice(
    staffUsername: string,
    payload: { fcmToken?: string },
  ) {
    const fcmToken = (payload.fcmToken ?? '').trim();
    if (!fcmToken) {
      throw new BadRequestException('fcmToken is required');
    }
    await (this.prisma as any).pushDevice.deleteMany({
      where: { staffUsername, fcmToken },
    });
    return { success: true };
  }
}
