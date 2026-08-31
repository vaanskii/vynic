import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../shared/prisma/prisma.service';
import { LEGACY_MANAGER_TENANT } from '../../tenancy/legacy-manager-tenant';

@Injectable()
export class UserService {
  constructor(private readonly prisma: PrismaService) {}

  async getProfile(userId: string) {
    const user = await this.prisma.websiteUser.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        firstName: true,
        lastName: true,
        phone: true,
        role: true,
        createdAt: true,
      },
    });

    if (!user) throw new Error('User not found');
    return user;
  }

  async getUserReservations(userId: string) {
    const user = await this.prisma.websiteUser.findUnique({
      where: { id: userId },
      select: { email: true },
    });
    if (!user) throw new Error('User not found');

    const reservations = await this.prisma.websiteReservation.findMany({
      where: {
        OR: [
          { userId },
          { AND: [{ userId: null }, { customerEmail: { not: null } }] },
        ],
        status: { in: ['CONFIRMED', 'COMPLETED'] },
      },
      include: {
        tables: { include: { table: true } },
        user: true,
      },
      orderBy: { date: 'desc' },
    });

    const userReservations = reservations.filter(
      (reservation) =>
        reservation.userId === userId ||
        (reservation.userId === null &&
          reservation.customerEmail === user.email),
    );

    return Promise.all(
      userReservations.map(async (reservation) => {
        let parsedMenuItems: Array<Record<string, unknown>> = [];

        if (reservation.menuItems) {
          try {
            const menuItemsData = JSON.parse(reservation.menuItems) as Array<{
              id: string;
              quantity: number;
              price?: number;
            }>;

            if (Array.isArray(menuItemsData) && menuItemsData.length > 0) {
              const menuItems = await this.prisma.menuItem.findMany({
                where: {
                  venueId: LEGACY_MANAGER_TENANT.venueId,
                  id: { in: menuItemsData.map((item) => item.id) },
                },
              });

              parsedMenuItems = menuItemsData.map((reservationItem) => {
                const dbItem = menuItems.find(
                  (item) => item.id === reservationItem.id,
                );
                return {
                  ...reservationItem,
                  name: dbItem?.nameEn || `Item ${reservationItem.id}`,
                  price: dbItem?.price || reservationItem.price,
                };
              });
            }
          } catch {
            parsedMenuItems = [];
          }
        }

        return {
          id: reservation.id,
          date: reservation.date,
          timeSlot: reservation.timeSlot,
          status: reservation.status,
          totalAmount: reservation.totalAmount,
          menuItems: parsedMenuItems,
          tables: reservation.tables.map((rt) => ({
            tableNumber: rt.table.websiteTableNumber,
            capacity: rt.table.capacity,
          })),
          customerName: reservation.customerName,
          customerEmail: reservation.customerEmail,
          customerPhone: reservation.customerPhone,
          notes: reservation.notes,
          createdAt: reservation.createdAt,
        };
      }),
    );
  }

  async updateProfile(
    userId: string,
    dto: { firstName: string; lastName: string },
  ) {
    return this.prisma.websiteUser.update({
      where: { id: userId },
      data: {
        firstName: dto.firstName,
        lastName: dto.lastName,
      },
      select: {
        id: true,
        phone: true,
        firstName: true,
        lastName: true,
      },
    });
  }
}
