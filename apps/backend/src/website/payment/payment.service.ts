import {
  Injectable,
  BadGatewayException,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import axios from 'axios';
import * as crypto from 'crypto';
import { MenuService } from '../menu/menu.service';
import type { TenantContext } from '../../tenancy/tenant-context';

import { PaymentIntegrationsService } from '../../payment-integrations/payment-integrations.service';
import { PrismaService } from '../../prisma.service';

@Injectable()
export class BogService {
  constructor(
    private readonly menuService: MenuService,
    private readonly integrations: PaymentIntegrationsService,
    private readonly db: PrismaService,
  ) {}

  private tokenUrl =
    'https://oauth2.bog.ge/auth/realms/bog/protocol/openid-connect/token';
  private orderUrl = 'https://api.bog.ge/payments/v1/ecommerce/orders';

  async getAccessToken(
    venueId: string,
    integrationId: string,
  ): Promise<string> {
    const { clientId, clientSecret } = await this.integrations.credentials(
      venueId,
      integrationId,
    );
    try {
      const auth = Buffer.from(`${clientId}:${clientSecret}`).toString(
        'base64',
      );
      const response = await axios.post(
        this.tokenUrl,
        'grant_type=client_credentials',
        {
          timeout: 15000,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            Authorization: `Basic ${auth}`,
          },
        },
      );
      if (typeof response.data.access_token !== 'string') throw Error();
      return response.data.access_token;
    } catch {
      throw new BadGatewayException('Payment provider authentication failed');
    }
  }

  async createOrder(
    tenant: TenantContext,
    integrationId: string,
    reservationId: string,
    totalAmount: number,
    language = 'en',
  ) {
    const current = await this.integrations.requireEnabled(tenant.venueId);
    if (current.id !== integrationId)
      throw new BadRequestException(
        'Payment configuration changed; retry booking',
      );
    const token = await this.getAccessToken(tenant.venueId, integrationId);
    const { returnOrigin } = await this.integrations.credentials(
      tenant.venueId,
      integrationId,
    );
    const amountInGel = Math.max(totalAmount, 1);
    const apiUrl =
      process.env.API_URL || `http://127.0.0.1:${process.env.PORT ?? 3000}`;

    const body = {
      callback_url: `${apiUrl}/api/bog/payment-callback`,
      external_order_id: reservationId,
      purchase_units: {
        currency: 'GEL',
        total_amount: amountInGel,
        basket: [
          {
            product_id: `reservation-${reservationId}`,
            description: 'Restaurant Table Reservation',
            quantity: 1,
            unit_price: amountInGel,
          },
        ],
      },
      redirect_urls: {
        success: `${returnOrigin}/${language}/payment-success?reservation_id=${reservationId}`,
        fail: `${returnOrigin}/${language}/payment-fail?reservation_id=${reservationId}`,
      },
      ttl: 30,
    };

    try {
      const response = await axios.post(this.orderUrl, body, {
        timeout: 15000,
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          'Accept-Language': 'ka',
        },
      });

      return response.data;
    } catch {
      throw new BadGatewayException('Payment provider order failed');
    }
  }

  async getPaymentDetails(orderId: string, venueId: string) {
    const reservation = await this.db.websiteReservation.findFirst({
      where: { paymentId: orderId, venueId },
    });
    if (!reservation?.paymentIntegrationId)
      throw new NotFoundException('Payment not found');
    const token = await this.getAccessToken(
      reservation.venueId,
      reservation.paymentIntegrationId,
    );
    try {
      const response = await axios.get(
        `https://api.bog.ge/payments/v1/receipt/${encodeURIComponent(orderId)}`,
        {
          headers: { Authorization: `Bearer ${token}` },
          timeout: 15000,
        },
      );
      if (response.data.external_order_id !== reservation.id) throw Error();
      return response.data;
    } catch {
      throw new BadGatewayException('Payment provider status failed');
    }
  }

  async preparePayment(tenant: TenantContext) {
    const row = await this.integrations.requireEnabled(tenant.venueId);
    await this.integrations.credentials(tenant.venueId, row.id);
    return row.id;
  }

  verifyCallbackSignature(requestBody: string, signature: string): boolean {
    try {
      const publicKey = `-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu4RUyAw3+CdkS3ZNILQh
zHI9Hemo+vKB9U2BSabppkKjzjjkf+0Sm76hSMiu/HFtYhqWOESryoCDJoqffY0Q
1VNt25aTxbj068QNUtnxQ7KQVLA+pG0smf+EBWlS1vBEAFbIas9d8c9b9sSEkTrr
TYQ90WIM8bGB6S/KLVoT1a7SnzabjoLc5Qf/SLDG5fu8dH8zckyeYKdRKSBJKvhx
tcBuHV4f7qsynQT+f2UYbESX/TLHwT5qFWZDHZ0YUOUIvb8n7JujVSGZO9/+ll/g
4ZIWhC1MlJgPObDwRkRd8NFOopgxMcMsDIZIoLbWKhHVq67hdbwpAq9K9WMmEhPn
PwIDAQAB
-----END PUBLIC KEY-----`;

      const verifier = crypto.createVerify('SHA256');
      verifier.update(requestBody);
      verifier.end();
      return verifier.verify(publicKey, signature, 'base64');
    } catch {
      return false;
    }
  }

  /**
   * Re-prices a cart from the Venue's own menu, ignoring client prices.
   *
   * Venue-scoped: an item id belonging to another restaurant is not found here,
   * so a cart cannot be priced against a menu the site does not sell.
   */
  async validateAndCalculateOrder(
    tenant: TenantContext,
    data: {
      menuItems: Array<{ id: string; quantity: number; price?: number }>;
      selectedTables: string[];
    },
  ) {
    const validatedMenuItems: Array<Record<string, unknown>> = [];
    let totalAmount = 0;

    if (data.menuItems?.length) {
      for (const item of data.menuItems) {
        const menuItem = await this.menuService.getMenuItemById(
          tenant,
          item.id,
        );
        if (!menuItem) {
          throw new Error(`Menu item with ID ${item.id} not found`);
        }

        const quantity = Math.max(1, Math.floor(Number(item.quantity) || 1));
        const realPrice = Number(menuItem.price);
        const itemTotal = realPrice * quantity;
        totalAmount += itemTotal;

        validatedMenuItems.push({
          id: item.id,
          quantity,
          price: realPrice,
          name: menuItem.translations.find((t) => t.language === 'en')?.name,
          imageUrl: menuItem.imageUrl,
          total: itemTotal,
          translations: {
            en: {
              name:
                menuItem.translations.find((t) => t.language === 'en')?.name ||
                item.id,
            },
            ka: {
              name:
                menuItem.translations.find((t) => t.language === 'ka')?.name ||
                item.id,
            },
          },
        });
      }
    }

    const subtotal = totalAmount;
    const serviceFee = subtotal > 0 ? subtotal * 0.1 : 0;
    totalAmount += serviceFee;
    totalAmount = Math.max(totalAmount, 1);

    return {
      menuItems: validatedMenuItems,
      subtotal,
      serviceFee,
      totalAmount,
      validationTimestamp: new Date().toISOString(),
    };
  }
}
