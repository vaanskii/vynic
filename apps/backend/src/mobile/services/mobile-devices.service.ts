import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { readRestaurantServiceFeeSettings } from '../util/mobile-date.util';
import type { TenantContext } from '../../tenancy/tenant-context';

/**
 * Device & settings endpoints for the mobile manager app:
 * restaurant settings, missed-notification replay, and push-device
 * registration (`/mobile/restaurant-settings`, `/mobile/notifications`,
 * `/mobile/push/register`, `/mobile/push/unregister`).
 *
 * Extracted verbatim from MobileController; the controller keeps the route
 * decorators and passes the authenticated Manager tenant and username through.
 * Notifications and push registrations are addressed by staff username, which
 * is only unique inside a Venue, so every query here is Venue-scoped.
 */
@Injectable()
export class MobileDevicesService {
  constructor(private readonly prisma: PrismaService) {}

  async getRestaurantSettings(tenant: TenantContext) {
    return readRestaurantServiceFeeSettings(this.prisma, tenant);
  }

  async getNotifications(
    tenant: TenantContext,
    username: string,
    since?: string,
  ) {
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
        notification: {
          venueId: tenant.venueId,
          createdAt: { gte: sinceDate },
        },
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
    tenant: TenantContext,
    staffUsername: string,
    payload: { fcmToken?: string; platform?: string },
  ) {
    const fcmToken = (payload.fcmToken ?? '').trim();
    if (!fcmToken) {
      throw new BadRequestException('fcmToken is required');
    }
    // fcmToken stays the identity because a device token genuinely is global:
    // re-registering the same handset for another Venue must move it, not
    // duplicate it.
    await this.prisma.pushDevice.upsert({
      where: { fcmToken },
      update: {
        venueId: tenant.venueId,
        staffUsername,
        platform: (payload.platform ?? '').trim() || null,
      },
      create: {
        venueId: tenant.venueId,
        staffUsername,
        fcmToken,
        platform: (payload.platform ?? '').trim() || null,
      },
    });
    return { success: true };
  }

  async unregisterPushDevice(
    tenant: TenantContext,
    staffUsername: string,
    payload: { fcmToken?: string },
  ) {
    const fcmToken = (payload.fcmToken ?? '').trim();
    if (!fcmToken) {
      throw new BadRequestException('fcmToken is required');
    }
    await this.prisma.pushDevice.deleteMany({
      where: { venueId: tenant.venueId, staffUsername, fcmToken },
    });
    return { success: true };
  }
}
