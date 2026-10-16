import {
  BadRequestException,
  Controller,
  Get,
  NotFoundException,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { PlatformAuthGuard } from './platform-auth.guard';
import { requireUuid } from './platform-validation';

/** Read-only operational evidence. Never exposes snapshots/customer contact or
 * provider references, and never retries/refunds/rebooks uncertain work. */
@Controller('platform/venues/:venueId/website-deliveries')
@UseGuards(PlatformAuthGuard)
export class PlatformWebsiteDeliveriesController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async read(
    @Param('venueId') input: string,
    @Query('offset') rawOffset?: string,
  ) {
    const venueId = requireUuid(input, 'venueId');
    const offset = rawOffset === undefined ? 0 : Number(rawOffset);
    if (!Number.isSafeInteger(offset) || offset < 0 || offset > 100_000)
      throw new BadRequestException('Invalid offset');
    const venue = await this.prisma.venue.findUnique({
      where: { id: venueId },
      select: { activeOperationalDeviceId: true },
    });
    if (!venue) throw new NotFoundException('Venue not found');
    const where = {
      venueId,
      OR: [
        { status: 'CONFIRMED' as const },
        { posReservationId: { not: null } },
        { deliveryIntents: { some: {} } },
      ],
    };
    const [total, bookings] = await Promise.all([
      this.prisma.websiteReservation.count({ where }),
      this.prisma.websiteReservation.findMany({
        where,
        skip: offset,
        take: 25,
        orderBy: [{ createdAt: 'desc' }, { id: 'asc' }],
        select: {
          id: true,
          status: true,
          date: true,
          timeSlot: true,
          posReservationId: true,
          deliveryIntents: {
            orderBy: { kind: 'desc' },
            select: {
              kind: true,
              status: true,
              proposedPosReservationId: true,
              queueId: true,
              queueTransport: true,
              lastErrorCode: true,
              attemptCount: true,
            },
          },
        },
      }),
    ]);
    const items = await Promise.all(
      bookings.map(async (booking) => {
        const deliveries = await Promise.all(
          booking.deliveryIntents.map(async (intent) => {
            let status = intent.status;
            let code = intent.lastErrorCode;
            if (intent.status === 'QUEUED' && intent.queueId) {
              if (intent.queueTransport === 'edge') {
                const receipt = await this.prisma.edgeCommand.findFirst({
                  where: { id: intent.queueId, venueId },
                  select: { status: true, resultCode: true },
                });
                status = !receipt
                  ? 'UNKNOWN'
                  : receipt.status === 'PENDING'
                    ? 'QUEUED'
                    : receipt.status;
                code = receipt?.resultCode ?? null;
              } else {
                const receipt = await this.prisma.posCallbackOutbox.findFirst({
                  where: { id: intent.queueId, venueId },
                  select: { status: true },
                });
                status = !receipt
                  ? 'UNKNOWN'
                  : receipt.status === 'delivered'
                    ? 'DELIVERED_LEGACY'
                    : receipt.status === 'failed'
                      ? 'FAILED'
                      : 'QUEUED';
              }
            }
            return {
              kind: intent.kind,
              status,
              code,
              attempts: intent.attemptCount,
              posReservationId: intent.proposedPosReservationId,
              commandId: intent.queueId,
              transport: intent.queueTransport,
            };
          }),
        );
        return {
          id: booking.id,
          bookingStatus: booking.status,
          date: booking.date,
          timeSlot: booking.timeSlot,
          posReservationId: booking.posReservationId,
          tracking: deliveries.some((delivery) => delivery.kind === 'CREATE')
            ? 'TRACKED'
            : 'UNTRACKED',
          deliveries,
        };
      }),
    );
    return {
      items,
      total,
      offset,
      limit: 25,
      primarySelected: venue.activeOperationalDeviceId !== null,
    };
  }
}
