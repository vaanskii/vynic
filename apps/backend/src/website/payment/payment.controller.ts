import {
  Controller,
  Post,
  Body,
  Headers,
  Get,
  Param,
  Req,
  HttpException,
  HttpStatus,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { BogService } from './payment.service';
import { FeatureKeys } from '../../entitlements/feature-keys';
import { FeatureGuard } from '../../entitlements/feature.guard';
import { RequiresFeature } from '../../entitlements/requires-feature.decorator';
import type { TenantContext } from '../../tenancy/tenant-context';
import { WebsiteTenant } from '../tenancy/website-tenant-context';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { ReservationService } from '../reservation/reservation.service';

/**
 * Payment entry points.
 *
 * Only order creation comes from a browser on a restaurant's site, so only it
 * resolves a Venue from the host. The status checks and the bank's callback
 * arrive without one — a payment provider has no reason to know the website
 * hostname — so they take their tenant from the server-owned reservation the
 * provider reference names. Guarding them on a host would break payments
 * without adding any authority the reservation row does not already carry.
 */
@Controller('api/bog')
export class BogController {
  constructor(
    private readonly bogService: BogService,
    private readonly reservationService: ReservationService,
  ) {}

  @Post('create-order')
  @UseGuards(WebsiteTenantGuard, FeatureGuard)
  @RequiresFeature(FeatureKeys.WEBSITE)
  async createOrder(
    @WebsiteTenant() tenant: TenantContext,
    @Body()
    body: {
      selectedTables: string[];
      selectedDate: string;
      selectedTime: string;
      menuItems?: Array<{ id: string; quantity: number; price?: number }>;
      totalAmount?: number;
      customerName?: string;
      customerEmail?: string;
      customerPhone?: string;
      userId?: string;
      notes?: string;
      language?: string;
      numberOfGuests?: number;
    },
  ) {
    const validatedData = await this.bogService.validateAndCalculateOrder(
      tenant,
      {
        menuItems: body.menuItems || [],
        selectedTables: body.selectedTables,
      },
    );

    const result = await this.reservationService.createReservation(tenant, {
      selectedTables: body.selectedTables,
      selectedDate: body.selectedDate,
      selectedTime: body.selectedTime,
      menuItems: validatedData.menuItems as Array<{
        id: string;
        quantity: number;
        price: number;
      }>,
      totalAmount: validatedData.totalAmount,
      customerName: body.customerName,
      customerEmail: body.customerEmail,
      customerPhone: body.customerPhone,
      userId: body.userId,
      notes: body.notes,
      language: body.language || 'en',
      numberOfGuests: body.numberOfGuests,
    });

    return {
      success: true,
      redirect_url: result.paymentUrl,
      reservation_id: result.reservation.id,
      message: 'Reservation created, redirect to payment',
      validation: {
        serverCalculatedTotal: validatedData.totalAmount,
        subtotal: validatedData.subtotal,
        serviceFee: validatedData.serviceFee,
        validatedItems: validatedData.menuItems,
        priceManipulationDetected:
          body.totalAmount !== validatedData.totalAmount,
        correctedCartItems: validatedData.menuItems,
      },
    };
  }

  @Get('check-status/:orderId')
  async checkOrderStatus(@Param('orderId') orderId: string) {
    try {
      const paymentDetails = await this.bogService.getPaymentDetails(orderId);
      const externalOrderId = paymentDetails.external_order_id;
      const status = paymentDetails.status || paymentDetails.order_status?.key;
      if (!externalOrderId) throw new Error('External order ID not found');

      const confirmedStatuses = [
        'completed',
        'partial_completed',
        'auth_requested',
      ];
      const failedStatuses = ['rejected', 'refunded', 'refunded_partially'];
      const statusKey = status?.toLowerCase() || 'unknown';
      const isSuccess = confirmedStatuses.includes(statusKey);
      const isFailed = failedStatuses.includes(statusKey);

      const reservation =
        await this.reservationService.updateReservationPaymentStatus(
          externalOrderId,
          status,
          isSuccess
            ? 'Payment confirmed via status check'
            : isFailed
              ? 'Payment failed (checked via status check)'
              : `Status check: ${status}`,
          orderId,
        );

      return {
        success: true,
        status: isSuccess ? 'CONFIRMED' : isFailed ? 'FAILED' : 'PENDING',
        reservation,
      };
    } catch {
      throw new HttpException(
        'Failed to check order status',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  @Get('check-reservation-status/:reservationId')
  async checkReservationStatus(@Param('reservationId') reservationId: string) {
    const paymentId =
      await this.reservationService.getPaymentIdByReservationId(reservationId);
    if (!paymentId) {
      return {
        success: false,
        message: 'Payment ID not found for this reservation',
      };
    }
    return this.checkOrderStatus(paymentId);
  }

  @Post('payment-callback')
  async handlePaymentCallback(
    @Req() req: Request & { rawBody?: Buffer },
    @Body()
    body: {
      event: string;
      zoned_request_time: string;
      body: {
        order_id?: string;
        external_order_id?: string;
        order_status?: { key?: string };
        payment_detail?: { code_description?: string };
      };
    },
    @Headers('callback-signature') signature?: string,
  ) {
    // Reject forged callbacks: require a valid RSA signature over the exact raw
    // request bytes BOG signed (not a re-serialized object). Must happen before
    // any reservation/payment state is touched.
    const rawBody = req.rawBody?.toString('utf8');
    if (
      !signature ||
      !rawBody ||
      !this.bogService.verifyCallbackSignature(rawBody, signature)
    ) {
      console.warn(
        '[BOG] Rejected payment callback — missing or invalid callback-signature',
      );
      throw new UnauthorizedException('Invalid callback signature');
    }

    if (body.event !== 'order_payment') {
      return { status: 'ignored', message: 'Unknown event type' };
    }

    const paymentData = body.body;
    const orderId = paymentData?.order_id;
    const externalOrderId = paymentData?.external_order_id;
    const orderStatus = paymentData?.order_status;
    const paymentDetail = paymentData?.payment_detail;

    if (!externalOrderId) {
      return { status: 'error', message: 'Missing external_order_id' };
    }
    if (!orderStatus?.key) {
      return { status: 'error', message: 'Missing order_status' };
    }

    const confirmedStatuses = [
      'completed',
      'partial_completed',
      'auth_requested',
    ];
    const failedStatuses = ['rejected', 'refunded', 'refunded_partially'];
    const statusKey = orderStatus.key.toLowerCase();
    const isSuccess = confirmedStatuses.includes(statusKey);
    const isFailed = failedStatuses.includes(statusKey);

    await this.reservationService.updateReservationPaymentStatus(
      externalOrderId,
      orderStatus.key,
      paymentDetail?.code_description ||
        (isSuccess
          ? 'Payment processed'
          : isFailed
            ? 'Payment Failed'
            : `Unknown status: ${statusKey}`),
      orderId || '',
    );

    return {
      status: 'success',
      message: isSuccess
        ? 'Payment confirmed and reservation created'
        : isFailed
          ? 'Payment failed'
          : `Payment status ${statusKey} recorded`,
      reservation_status: isSuccess
        ? 'CONFIRMED'
        : isFailed
          ? 'FAILED'
          : 'PENDING',
    };
  }
}
