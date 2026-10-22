import { createHash } from 'node:crypto';
import { bogPaymentFacts } from './bog-payment-facts';
import {
  Controller,
  Post,
  Body,
  Headers,
  Get,
  Param,
  Req,
  HttpCode,
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
import {
  RequiresWebsiteCapability,
  WebsiteCapabilityGuard,
} from '../tenancy/website-capability.guard';
import { WebsiteTenantGuard } from '../tenancy/website-tenant.guard';
import { WebsiteAuthService } from '../auth/auth.service';
import { ReservationService } from '../reservation/reservation.service';

/**
 * Payment entry points.
 *
 * Browser requests resolve their Venue from the registered website host.
 * Receipt requests additionally require a payment stored for that Venue.
 * Bank callbacks use signed server-owned reservation/payment references, without
 * website entitlement checks, so in-flight payments settle after access changes.
 */
@Controller('api/bog')
export class BogController {
  constructor(
    private readonly bogService: BogService,
    private readonly reservationService: ReservationService,
    private readonly authService: WebsiteAuthService,
  ) {}

  @Post('create-order')
  @UseGuards(WebsiteTenantGuard, FeatureGuard, WebsiteCapabilityGuard)
  @RequiresFeature(FeatureKeys.WEBSITE)
  @RequiresWebsiteCapability('RESERVATIONS', 'ONLINE_PAYMENTS')
  async createOrder(
    @WebsiteTenant() tenant: TenantContext,
    @Req() request: Request,
    @Body() body: unknown,
  ) {
    const user = await this.authService.tryGetUserFromRequest(request);
    const result = await this.reservationService.createReservation(
      tenant,
      body,
      user?.id,
    );
    return {
      success: true,
      redirect_url: result.paymentUrl,
      reservation_id: result.reservation.id,
      message: 'Reservation created, redirect to payment',
      validation: {
        ...result.validation,
        // Existing Vankisi carts identify variant selections by the variant ID.
        // Preserve that request shape when the client replaces a corrected cart.
        correctedCartItems: result.validation.validatedItems.map((item) => ({
          ...item,
          id: item.variantId ?? item.id,
        })),
      },
    };
  }

  @Get('check-status/:orderId')
  @UseGuards(WebsiteTenantGuard)
  async checkOrderStatus(
    @WebsiteTenant() tenant: TenantContext,
    @Param('orderId') orderId: string,
  ) {
    try {
      const receipt: unknown = await this.bogService.getPaymentDetails(
        orderId,
        tenant.venueId,
      );
      const facts = bogPaymentFacts(receipt);
      if (!facts.reservationId || facts.orderId !== orderId)
        throw new HttpException(
          'Payment reference mismatch',
          HttpStatus.BAD_REQUEST,
        );
      const updated =
        await this.reservationService.updateReservationPaymentStatus(
          facts.reservationId,
          facts.status,
          '',
          orderId,
          { source: 'POLL', observedAt: new Date(), receipt },
        );
      // Anonymous return routes expose only current booking outcome, never the row.
      return {
        success: true,
        status: updated.paymentReviewReason ? 'REVIEW' : updated.status,
      };
    } catch (error) {
      if (error instanceof HttpException) throw error;
      throw new HttpException(
        'Failed to check order status',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
  }

  @Get('check-reservation-status/:reservationId')
  @UseGuards(WebsiteTenantGuard)
  async checkReservationStatus(
    @WebsiteTenant() tenant: TenantContext,
    @Param('reservationId') reservationId: string,
  ) {
    const paymentId = await this.reservationService.getPaymentIdByReservationId(
      reservationId,
      tenant.venueId,
    );
    if (!paymentId) {
      return {
        success: false,
        message: 'Payment ID not found for this reservation',
      };
    }
    return this.checkOrderStatus(tenant, paymentId);
  }

  @Post('payment-callback')
  @HttpCode(HttpStatus.OK)
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

    if (!orderId) return { status: 'error', message: 'Missing order_id' };
    let receipt: unknown = null;
    try {
      receipt = await this.bogService.getPaymentDetailsForReservation(
        externalOrderId,
        orderId,
      );
    } catch (error) {
      // Reference/ownership failures never become a financial observation.
      if (error instanceof HttpException && error.getStatus() < 500)
        throw error;
      // A signed notification survives provider read failure as durable review;
      // its pinned reference is retried by the reconciliation worker.
    }
    const updated =
      await this.reservationService.updateReservationPaymentStatus(
        externalOrderId,
        orderStatus.key,
        paymentDetail?.code_description ?? '',
        orderId,
        {
          source: 'CALLBACK',
          observedAt: new Date(),
          receipt,
          signedCallback: {
            fingerprint: createHash('sha256').update(rawBody).digest('hex'),
            sentAt: body.zoned_request_time,
            receipt: paymentData,
          },
        },
      );
    return {
      status: 'success',
      message: updated.paymentReviewReason
        ? 'Payment requires restaurant review'
        : 'Payment outcome recorded',
      reservation_status: updated.paymentReviewReason
        ? 'REVIEW'
        : updated.status,
    };
  }
}
