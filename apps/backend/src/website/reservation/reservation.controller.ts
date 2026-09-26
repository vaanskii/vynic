import {
  BadRequestException,
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { WebsiteUserRole } from '@prisma/client';
import type { Request } from 'express';
import { WebsiteAuthService } from '../auth/auth.service';
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
import { ReservationService } from './reservation.service';

interface CreateReservationDto {
  selectedTables: string[];
  selectedDate: string;
  selectedTime: string;
  menuItems?: Array<{ id: string; quantity: number; price: number }>;
  totalAmount?: number;
  customerName?: string;
  customerEmail?: string;
  customerPhone?: string;
  /** Ignored: the booking's account comes from the session cookie. */
  userId?: string;
  notes?: string;
  numberOfGuests?: number;
}

/**
 * Public tables, availability and bookings for the restaurant that owns the
 * requested host. Every handler is scoped to that Venue; none of them accepts a
 * venue identifier from the caller. Bookings belong to the shared custom-site
 * surface, so only a CUSTOM Venue's host is served.
 */
@Controller('api/tables')
@UseGuards(WebsiteTenantGuard, FeatureGuard, WebsiteCapabilityGuard)
@RequiresFeature(FeatureKeys.WEBSITE)
@RequiresWebsiteCapability('RESERVATIONS')
export class TableController {
  constructor(
    private readonly reservationService: ReservationService,
    private readonly authService: WebsiteAuthService,
  ) {}

  @Get()
  async getAllTables(@WebsiteTenant() tenant: TenantContext) {
    return this.reservationService.getAllTables(tenant);
  }

  @Get('availability')
  async getTableAvailability(
    @WebsiteTenant() tenant: TenantContext,
    @Query('date') date: string,
  ) {
    if (!date) throw new BadRequestException('Date parameter is required');
    return this.reservationService.getTableAvailability(tenant, date);
  }

  @Get('availability/:tableNumber')
  async checkTableAvailability(
    @WebsiteTenant() tenant: TenantContext,
    @Param('tableNumber') tableNumber: string,
    @Query('date') date: string,
    @Query('timeSlot') timeSlot: string,
  ) {
    if (!date || !timeSlot) {
      throw new BadRequestException(
        'Date and timeSlot parameters are required',
      );
    }
    const isAvailable = await this.reservationService.isTableAvailable(
      tenant,
      tableNumber,
      date,
      timeSlot,
    );
    return { tableNumber, date, timeSlot, isAvailable };
  }

  @Post('reservations')
  async createReservation(
    @WebsiteTenant() tenant: TenantContext,
    @Body() data: CreateReservationDto,
    @Req() request: Request,
  ) {
    // A browser-supplied account id would let anyone attach a booking to
    // someone else's account; only the signed-in customer's own id is used.
    const user = await this.authService.tryGetUserFromRequest(request);
    return this.reservationService.createReservation(tenant, {
      ...data,
      userId: user?.id,
    });
  }

  /**
   * Public map: returns table availability for the date (no login).
   * SUPER_ADMIN with auth cookie: full reservation list for admin UI, only for
   * the Venue that administrator is bound to — WebsiteUser is global, so the
   * role alone must never open another restaurant's booking list.
   */
  @Get('reservations')
  async getReservationsForDate(
    @WebsiteTenant() tenant: TenantContext,
    @Query('date') date: string,
    @Req() request: Request,
  ) {
    if (!date) throw new BadRequestException('Date parameter is required');

    const user = await this.authService.tryGetUserFromRequest(request);
    if (
      user?.role === WebsiteUserRole.SUPER_ADMIN &&
      user.adminVenueId === tenant.venueId
    ) {
      return this.reservationService.getReservationsForDate(tenant, date);
    }

    return this.reservationService.getPublicMapReservations(tenant, date);
  }
}
