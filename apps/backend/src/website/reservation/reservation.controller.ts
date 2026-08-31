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
  userId?: string;
  notes?: string;
  numberOfGuests?: number;
}

/**
 * Public tables, availability and bookings for the restaurant that owns the
 * requested host. Every handler is scoped to that Venue; none of them accepts a
 * venue identifier from the caller.
 */
@Controller('api/tables')
@UseGuards(WebsiteTenantGuard, FeatureGuard)
@RequiresFeature(FeatureKeys.WEBSITE)
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
  ) {
    return this.reservationService.createReservation(tenant, data);
  }

  /**
   * Public map: returns table availability for the date (no login).
   * SUPER_ADMIN with auth cookie: full reservation list for admin UI.
   */
  @Get('reservations')
  async getReservationsForDate(
    @WebsiteTenant() tenant: TenantContext,
    @Query('date') date: string,
    @Req() request: Request,
  ) {
    if (!date) throw new BadRequestException('Date parameter is required');

    const user = await this.authService.tryGetUserFromRequest(request);
    if (user?.role === WebsiteUserRole.SUPER_ADMIN) {
      return this.reservationService.getReservationsForDate(tenant, date);
    }

    return this.reservationService.getPublicMapReservations(tenant, date);
  }
}
