import { StaffRole as PrismaStaffRole, VenueStatus } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { ManagerTenantService } from './manager-tenant.service';

interface StaffFixture {
  role?: PrismaStaffRole;
  isActive?: boolean;
  venueStatus?: VenueStatus;
  venueId?: string;
  organizationId?: string;
}

function makeService(fixture: StaffFixture | null) {
  const staff = {
    findUnique: jest.fn(() =>
      Promise.resolve(
        fixture === null
          ? null
          : {
              id: 'staff-1',
              username: 'manager-a',
              role: fixture.role ?? PrismaStaffRole.MANAGER,
              isActive: fixture.isActive ?? true,
              venue: {
                id: fixture.venueId ?? 'venue-a',
                organizationId: fixture.organizationId ?? 'org-1',
                status: fixture.venueStatus ?? VenueStatus.ACTIVE,
              },
            },
      ),
    ),
  };
  const prisma = { staff } as unknown as PrismaService;
  return { service: new ManagerTenantService(prisma), staff };
}

describe('ManagerTenantService', () => {
  it('resolves the Venue from the Staff row rather than anything a client sent', async () => {
    const { service, staff } = makeService({
      venueId: 'venue-a',
      organizationId: 'org-1',
    });

    await expect(service.resolveByStaffId('staff-1')).resolves.toEqual({
      staffId: 'staff-1',
      username: 'manager-a',
      role: 'MANAGER',
      venueId: 'venue-a',
      organizationId: 'org-1',
    });
    // Looked up by identity only — no venue was accepted as an input.
    expect(staff.findUnique).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'staff-1' } }),
    );
  });

  it('carries the Organization that owns the resolved Venue', async () => {
    const { service } = makeService({
      venueId: 'venue-b',
      organizationId: 'org-2',
    });

    await expect(service.resolveByStaffId('staff-1')).resolves.toMatchObject({
      venueId: 'venue-b',
      organizationId: 'org-2',
    });
  });

  it('refuses a staff member who no longer exists', async () => {
    const { service } = makeService(null);

    await expect(service.resolveByStaffId('staff-1')).resolves.toBeNull();
  });

  it('refuses a deactivated staff member even mid-token', async () => {
    const { service } = makeService({ isActive: false });

    await expect(service.resolveByStaffId('staff-1')).resolves.toBeNull();
  });

  it('refuses a role that may not use the manager app', async () => {
    const { service } = makeService({ role: PrismaStaffRole.WAITER });

    await expect(service.resolveByStaffId('staff-1')).resolves.toBeNull();
  });

  it('accepts the legacy ADMIN role the same way login does', async () => {
    const { service } = makeService({ role: PrismaStaffRole.ADMIN });

    await expect(service.resolveByStaffId('staff-1')).resolves.toMatchObject({
      role: 'MANAGER',
    });
  });

  it('refuses a staff member whose Venue has been disabled', async () => {
    const { service } = makeService({ venueStatus: VenueStatus.DISABLED });

    await expect(service.resolveByStaffId('staff-1')).resolves.toBeNull();
  });

  it('refuses an empty subject without touching the database', async () => {
    const { service, staff } = makeService({});

    await expect(service.resolveByStaffId('')).resolves.toBeNull();
    expect(staff.findUnique).not.toHaveBeenCalled();
  });
});
