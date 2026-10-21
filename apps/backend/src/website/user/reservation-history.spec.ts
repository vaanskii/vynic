import type { PrismaService } from '../../prisma.service';
import { UserService } from './user.service';

describe('website reservation menu history', () => {
  function fixture(menuItems: unknown[]) {
    const db = {
      websiteUser: {
        findUnique: jest.fn().mockResolvedValue({ id: 'customer' }),
      },
      websiteReservation: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'booking',
            menuItems: JSON.stringify(menuItems),
            tables: [],
          },
        ]),
      },
      menuItem: {
        findMany: jest
          .fn()
          .mockResolvedValue([
            { id: 'drink', nameEn: 'Renamed drink', price: 99 },
          ]),
      },
    };
    return new UserService(db as unknown as PrismaService);
  }
  const tenant = { venueId: 'venue-a', organizationId: 'org-a' };

  it('preserves paid variant names and exact unit prices after catalog changes', async () => {
    const frozen = [
      {
        id: 'drink',
        variantId: 'large',
        name: 'Original drink 1L',
        price: 12.5,
        quantity: 2,
      },
      { id: 'drink', name: 'Complimentary', price: 0, quantity: 1 },
    ];
    const [reservation] = await fixture(frozen).getUserReservations(
      tenant,
      'customer',
    );
    expect(reservation.menuItems).toEqual(frozen);
  });

  it('completes legacy snapshots only where name or price is absent', async () => {
    const [reservation] = await fixture([
      { id: 'drink', price: 12.5, quantity: 2 },
      { id: 'missing', name: 'Retained dish', price: 4, quantity: 1 },
      { id: 'drink', name: 'Legacy name', quantity: 1 },
    ]).getUserReservations(tenant, 'customer');
    expect(reservation.menuItems).toEqual([
      { id: 'drink', name: 'Renamed drink', price: 12.5, quantity: 2 },
      { id: 'missing', name: 'Retained dish', price: 4, quantity: 1 },
      { id: 'drink', name: 'Legacy name', price: 99, quantity: 1 },
    ]);
  });
});
