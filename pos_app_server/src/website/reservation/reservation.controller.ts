import {
  BadRequestException,
  Controller,
  Get,
  Post,
  Body,
  Param,
  Query,
  Req,
} from '@nestjs/common';
import { WebsiteUserRole } from '@prisma/client';
import type { Request } from 'express';
import { WebsiteAuthService } from '../auth/auth.service';
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

@Controller('api/tables')
export class TableController {
  constructor(
    private readonly reservationService: ReservationService,
    private readonly authService: WebsiteAuthService,
  ) {}

  @Get()
  async getAllTables() {
    return this.reservationService.getAllTables();
  }

  @Get('availability')
  async getTableAvailability(@Query('date') date: string) {
    if (!date) throw new BadRequestException('Date parameter is required');
    return this.reservationService.getTableAvailability(date);
  }

  @Get('availability/:tableNumber')
  async checkTableAvailability(
    @Param('tableNumber') tableNumber: string,
    @Query('date') date: string,
    @Query('timeSlot') timeSlot: string,
  ) {
    if (!date || !timeSlot) {
      throw new BadRequestException('Date and timeSlot parameters are required');
    }
    const isAvailable = await this.reservationService.isTableAvailable(
      tableNumber,
      date,
      timeSlot,
    );
    return { tableNumber, date, timeSlot, isAvailable };
  }

  @Post('reservations')
  async createReservation(@Body() data: CreateReservationDto) {
    return this.reservationService.createReservation(data);
  }

  /**
   * Public map: returns table availability for the date (no login).
   * SUPER_ADMIN with auth cookie: full reservation list for admin UI.
   */
  @Get('reservations')
  async getReservationsForDate(
    @Query('date') date: string,
    @Req() request: Request,
  ) {
    if (!date) throw new BadRequestException('Date parameter is required');

    const user = await this.authService.tryGetUserFromRequest(request);
    if (user?.role === WebsiteUserRole.SUPER_ADMIN) {
      return this.reservationService.getReservationsForDate(date);
    }

    return this.reservationService.getPublicMapReservations(date);
  }
}
