import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../prisma.service';
import { PosCommandDispatcher } from '../../pos/pos-command-dispatcher.service';
import { EdgeCommandTypes } from '../../shared/contracts/edge-command';
import { StaffPinVault } from '../../auth/staff-pin-vault.service';
import {
  ASSIGNABLE_STAFF_ROLES,
  normalizeStaffRole,
  StaffRole,
  toClientRole,
} from '../../staff/staff-role';
import { staffIdentity } from '../../tenancy/tenant-identity';
import type { TenantContext } from '../../tenancy/tenant-context';

/**
 * Staff/user management for the mobile manager app (`/mobile/users*`).
 *
 * Extracted verbatim from MobileController as the first service-split pilot;
 * behavior is unchanged. The controller keeps the route decorators and
 * delegates to these methods.
 */
@Injectable()
export class MobileUsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly posCommands: PosCommandDispatcher,
    private readonly pinVault: StaffPinVault,
  ) {}

  /**
   * Record a staff change for this Venue's POS to apply.
   *
   * Every one of these is convergent: the payload states what the record should
   * look like, so a redelivery lands on the same user rather than a second one.
   * That is what lets them ride an at-least-once transport at all.
   *
   * The cloud row is already written when this runs — Cloud owns staff identity
   * and the POS holds a cache of it — so a POS that is offline delays the change
   * reaching the terminal rather than failing the request.
   */
  private dispatchStaffCommand(
    tenant: TenantContext,
    type: Parameters<PosCommandDispatcher['dispatch']>[1]['type'],
    payload: Record<string, unknown>,
  ) {
    return this.posCommands.dispatch(tenant, { type, payload });
  }

  async getUsers(tenant: TenantContext) {
    const pinsMap = await this.pinVault.read();
    const staff = await this.prisma.staff.findMany({
      where: { venueId: tenant.venueId },
      orderBy: [{ role: 'asc' }, { username: 'asc' }],
      select: {
        id: true,
        username: true,
        role: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    return staff.map((u: any) => ({
      ...u,
      pinCode: pinsMap[u.username] ?? '',
    }));
  }

  async createUser(
    tenant: TenantContext,
    payload: {
      username?: string;
      pinCode?: string;
      role?: string;
    },
  ) {
    const username = (payload.username ?? '').trim();
    const pinCode = (payload.pinCode ?? '').trim();
    const role = normalizeStaffRole(payload.role);
    if (!username || !pinCode) {
      throw new BadRequestException('username and pinCode are required');
    }
    if (!ASSIGNABLE_STAFF_ROLES.includes(role)) {
      throw new BadRequestException(
        'role must be MANAGER, SUPERVISOR, or WAITER',
      );
    }
    const existing = await (this.prisma as any).staff.findUnique({
      where: staffIdentity(tenant, username),
      select: { id: true },
    });
    if (existing) {
      throw new BadRequestException('username already exists');
    }
    const pinHash = await bcrypt.hash(pinCode, 12);
    const created = await (this.prisma as any).staff.create({
      data: {
        venueId: tenant.venueId,
        username,
        pinHash,
        role,
        isActive: true,
      },
      select: {
        id: true,
        username: true,
        role: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    const pinsMap = await this.pinVault.read();
    pinsMap[username] = pinCode;
    await this.pinVault.write(pinsMap);
    const posDelivery = await this.dispatchStaffCommand(
      tenant,
      EdgeCommandTypes.STAFF_CREATE,
      { username, pinCode, role: toClientRole(role) },
    );
    return { ...created, pinCode, posDelivery };
  }

  async updateUserPin(
    tenant: TenantContext,
    usernameParam: string,
    payload: { pinCode?: string },
  ) {
    const username = (usernameParam ?? '').trim();
    const pinCode = (payload.pinCode ?? '').trim();
    if (!username || !pinCode) {
      throw new BadRequestException('username and pinCode are required');
    }
    const existing = await (this.prisma as any).staff.findUnique({
      where: staffIdentity(tenant, username),
      select: {
        id: true,
        role: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }
    const pinHash = await bcrypt.hash(pinCode, 12);
    await (this.prisma as any).staff.update({
      where: staffIdentity(tenant, username),
      data: { pinHash },
    });
    const pinsMap = await this.pinVault.read();
    pinsMap[username] = pinCode;
    await this.pinVault.write(pinsMap);
    const posDelivery = await this.dispatchStaffCommand(
      tenant,
      EdgeCommandTypes.STAFF_PIN_UPDATE,
      { username, pinCode },
    );
    return {
      username,
      role: existing.role,
      isActive: existing.isActive,
      pinCode,
      posDelivery,
    };
  }

  async updateUserRole(
    tenant: TenantContext,
    usernameParam: string,
    payload: { role?: string },
  ) {
    const username = (usernameParam ?? '').trim();
    const role = normalizeStaffRole(payload.role);
    if (!username || !payload.role) {
      throw new BadRequestException('username and role are required');
    }
    if (!ASSIGNABLE_STAFF_ROLES.includes(role)) {
      throw new BadRequestException(
        'role must be MANAGER, SUPERVISOR, or WAITER',
      );
    }

    const existing = await (this.prisma as any).staff.findUnique({
      where: staffIdentity(tenant, username),
      select: { id: true, role: true, isActive: true },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }

    if (
      normalizeStaffRole(existing.role) === StaffRole.MANAGER &&
      role !== StaffRole.MANAGER
    ) {
      const managerCount = await (this.prisma as any).staff.count({
        where: {
          venueId: tenant.venueId,
          role: { in: ['ADMIN', 'MANAGER'] },
          isActive: true,
        },
      });
      if (managerCount <= 1) {
        throw new BadRequestException('Cannot change the last manager role');
      }
    }

    const updated = await (this.prisma as any).staff.update({
      where: staffIdentity(tenant, username),
      data: { role },
      select: {
        id: true,
        username: true,
        role: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    const posDelivery = await this.dispatchStaffCommand(
      tenant,
      EdgeCommandTypes.STAFF_ROLE_UPDATE,
      { username, role: toClientRole(role) },
    );
    return { ...updated, posDelivery };
  }

  async renameUser(
    tenant: TenantContext,
    usernameParam: string,
    payload: { username?: string },
  ) {
    const oldUsername = (usernameParam ?? '').trim();
    const newUsername = (payload.username ?? '').trim();
    if (!oldUsername || !newUsername) {
      throw new BadRequestException('username is required');
    }
    if (oldUsername === newUsername) {
      return { username: newUsername };
    }
    const existing = await (this.prisma as any).staff.findUnique({
      where: staffIdentity(tenant, oldUsername),
      select: {
        id: true,
        role: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }
    const conflict = await (this.prisma as any).staff.findUnique({
      where: staffIdentity(tenant, newUsername),
      select: { id: true },
    });
    if (conflict) {
      throw new BadRequestException('username already exists');
    }
    const updated = await (this.prisma as any).staff.update({
      where: staffIdentity(tenant, oldUsername),
      data: { username: newUsername },
      select: {
        id: true,
        username: true,
        role: true,
        isActive: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    const pinsMap = await this.pinVault.read();
    const pinCode = pinsMap[oldUsername] ?? '';
    if (pinCode) {
      delete pinsMap[oldUsername];
      pinsMap[newUsername] = pinCode;
      await this.pinVault.write(pinsMap);
    }
    const posDelivery = await this.dispatchStaffCommand(
      tenant,
      EdgeCommandTypes.STAFF_RENAME,
      { oldUsername, newUsername },
    );
    return { ...updated, pinCode, posDelivery };
  }

  async deleteUser(tenant: TenantContext, usernameParam: string) {
    const username = (usernameParam ?? '').trim();
    const existing = await (this.prisma as any).staff.findUnique({
      where: staffIdentity(tenant, username),
      select: { id: true, role: true },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }
    if (normalizeStaffRole(existing.role) === StaffRole.MANAGER) {
      const managerCount = await (this.prisma as any).staff.count({
        where: {
          venueId: tenant.venueId,
          role: { in: ['ADMIN', 'MANAGER'] },
          isActive: true,
        },
      });
      if (managerCount <= 1) {
        throw new BadRequestException('Cannot delete the last manager');
      }
    }
    await (this.prisma as any).staff.delete({
      where: staffIdentity(tenant, username),
    });
    const pinsMap = await this.pinVault.read();
    delete pinsMap[username];
    await this.pinVault.write(pinsMap);
    const posDelivery = await this.dispatchStaffCommand(
      tenant,
      EdgeCommandTypes.STAFF_DELETE,
      { username },
    );
    return { success: true, posDelivery };
  }
}
