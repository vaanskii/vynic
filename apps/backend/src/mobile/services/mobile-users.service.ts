import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../prisma.service';
import { PosCallbackClient } from '../../pos/pos-callback.client';
import { PosOutboxService } from '../../pos/pos-outbox.service';
import { StaffPinVault } from '../../auth/staff-pin-vault.service';
import {
  ASSIGNABLE_STAFF_ROLES,
  normalizeStaffRole,
  StaffRole,
  toClientRole,
} from '../../staff/staff-role';
import {
  LEGACY_MANAGER_TENANT,
  legacyStaffIdentity,
} from '../../tenancy/legacy-manager-tenant';

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
    private readonly posCallback: PosCallbackClient,
    private readonly posOutbox: PosOutboxService,
    private readonly pinVault: StaffPinVault,
  ) {}

  /**
   * Shared handler for a failed direct POS-callback push. The cloud DB is
   * already updated (source of truth here), so we always log; and when the
   * failure means the POS was simply offline, we queue the change for durable
   * delivery so it reaches POS Hive once the POS reconnects.
   */
  private async queueIfPosUnreachable(
    context: string,
    endpoint: string,
    payload: Record<string, unknown>,
    error: unknown,
  ): Promise<void> {
    console.warn(
      `[Mobile][Users] POS ${context} failed:`,
      (error as Error).message,
    );
    if (this.posOutbox.isPosUnreachableError(error)) {
      await this.posOutbox.enqueue({ endpoint, payload });
    }
  }

  async getUsers() {
    const pinsMap = await this.pinVault.read();
    const staff = await this.prisma.staff.findMany({
      where: { venueId: LEGACY_MANAGER_TENANT.venueId },
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

  async createUser(payload: {
    username?: string;
    pinCode?: string;
    role?: string;
  }) {
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
      where: legacyStaffIdentity(username),
      select: { id: true },
    });
    if (existing) {
      throw new BadRequestException('username already exists');
    }
    const pinHash = await bcrypt.hash(pinCode, 12);
    const created = await (this.prisma as any).staff.create({
      data: {
        venueId: LEGACY_MANAGER_TENANT.venueId,
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
    const posUserPayload = { username, pinCode, role: toClientRole(role) };
    try {
      await this.posCallback.createPosUser(posUserPayload);
    } catch (e) {
      await this.queueIfPosUnreachable(
        'create user',
        '/mobile-user-create',
        posUserPayload,
        e,
      );
    }
    return { ...created, pinCode };
  }

  async updateUserPin(usernameParam: string, payload: { pinCode?: string }) {
    const username = (usernameParam ?? '').trim();
    const pinCode = (payload.pinCode ?? '').trim();
    if (!username || !pinCode) {
      throw new BadRequestException('username and pinCode are required');
    }
    const existing = await (this.prisma as any).staff.findUnique({
      where: legacyStaffIdentity(username),
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
      where: legacyStaffIdentity(username),
      data: { pinHash },
    });
    const pinsMap = await this.pinVault.read();
    pinsMap[username] = pinCode;
    await this.pinVault.write(pinsMap);
    try {
      await this.posCallback.updatePosUserPin({ username, pinCode });
    } catch (e) {
      await this.queueIfPosUnreachable(
        'update pin',
        '/mobile-user-update-pin',
        { username, pinCode },
        e,
      );
    }
    return {
      username,
      role: existing.role,
      isActive: existing.isActive,
      pinCode,
    };
  }

  async updateUserRole(usernameParam: string, payload: { role?: string }) {
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
      where: legacyStaffIdentity(username),
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
          venueId: LEGACY_MANAGER_TENANT.venueId,
          role: { in: ['ADMIN', 'MANAGER'] },
          isActive: true,
        },
      });
      if (managerCount <= 1) {
        throw new BadRequestException('Cannot change the last manager role');
      }
    }

    const updated = await (this.prisma as any).staff.update({
      where: legacyStaffIdentity(username),
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
    try {
      await this.posCallback.updatePosUserRole({
        username,
        role: toClientRole(role),
      });
    } catch (e) {
      await this.queueIfPosUnreachable(
        'update role',
        '/mobile-user-update-role',
        { username, role: toClientRole(role) },
        e,
      );
    }
    return updated;
  }

  async renameUser(usernameParam: string, payload: { username?: string }) {
    const oldUsername = (usernameParam ?? '').trim();
    const newUsername = (payload.username ?? '').trim();
    if (!oldUsername || !newUsername) {
      throw new BadRequestException('username is required');
    }
    if (oldUsername === newUsername) {
      return { username: newUsername };
    }
    const existing = await (this.prisma as any).staff.findUnique({
      where: legacyStaffIdentity(oldUsername),
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
      where: legacyStaffIdentity(newUsername),
      select: { id: true },
    });
    if (conflict) {
      throw new BadRequestException('username already exists');
    }
    const updated = await (this.prisma as any).staff.update({
      where: legacyStaffIdentity(oldUsername),
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
    try {
      await this.posCallback.renamePosUser({
        oldUsername,
        newUsername,
      });
    } catch (e) {
      await this.queueIfPosUnreachable(
        'rename user',
        '/mobile-user-rename',
        { oldUsername, newUsername },
        e,
      );
    }
    return { ...updated, pinCode };
  }

  async deleteUser(usernameParam: string) {
    const username = (usernameParam ?? '').trim();
    const existing = await (this.prisma as any).staff.findUnique({
      where: legacyStaffIdentity(username),
      select: { id: true, role: true },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }
    if (normalizeStaffRole(existing.role) === StaffRole.MANAGER) {
      const managerCount = await (this.prisma as any).staff.count({
        where: {
          venueId: LEGACY_MANAGER_TENANT.venueId,
          role: { in: ['ADMIN', 'MANAGER'] },
          isActive: true,
        },
      });
      if (managerCount <= 1) {
        throw new BadRequestException('Cannot delete the last manager');
      }
    }
    await (this.prisma as any).staff.delete({
      where: legacyStaffIdentity(username),
    });
    const pinsMap = await this.pinVault.read();
    delete pinsMap[username];
    await this.pinVault.write(pinsMap);
    try {
      await this.posCallback.deletePosUser({ username });
    } catch (e) {
      await this.queueIfPosUnreachable(
        'delete user',
        '/mobile-user-delete',
        { username },
        e,
      );
    }
    return { success: true };
  }
}
