import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from './prisma.service';
import { PosCallbackClient } from './pos/pos-callback.client';
import {
  ASSIGNABLE_STAFF_ROLES,
  normalizeStaffRole,
  StaffRole,
  toClientRole,
} from './staff/staff-role';

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
  ) {}

  async getUsers() {
    const pinsSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'staff:plain_pins' },
      select: { value: true },
    });
    let pinsMap: Record<string, string> = {};
    if (pinsSetting?.value) {
      try {
        pinsMap = JSON.parse(pinsSetting.value) as Record<string, string>;
      } catch {
        pinsMap = {};
      }
    }
    const staff = await this.prisma.staff.findMany({
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
      where: { username },
      select: { id: true },
    });
    if (existing) {
      throw new BadRequestException('username already exists');
    }
    const pinHash = await bcrypt.hash(pinCode, 12);
    const created = await (this.prisma as any).staff.create({
      data: { username, pinHash, role, isActive: true },
      select: { id: true, username: true, role: true, isActive: true, createdAt: true, updatedAt: true },
    });
    const pinsSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'staff:plain_pins' },
      select: { value: true },
    });
    let pinsMap: Record<string, string> = {};
    if (pinsSetting?.value) {
      try {
        pinsMap = JSON.parse(pinsSetting.value) as Record<string, string>;
      } catch {
        pinsMap = {};
      }
    }
    pinsMap[username] = pinCode;
    await (this.prisma as any).setting.upsert({
      where: { key: 'staff:plain_pins' },
      update: { value: JSON.stringify(pinsMap) },
      create: { key: 'staff:plain_pins', value: JSON.stringify(pinsMap) },
    });
    try {
      await this.posCallback.createPosUser({
        username,
        pinCode,
        role: toClientRole(role),
      });
    } catch (e) {
      console.warn('[Mobile][Users] POS create user failed:', (e as Error).message);
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
      where: { username },
      select: { id: true, role: true, isActive: true, createdAt: true, updatedAt: true },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }
    const pinHash = await bcrypt.hash(pinCode, 12);
    await (this.prisma as any).staff.update({
      where: { username },
      data: { pinHash },
    });
    const pinsSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'staff:plain_pins' },
      select: { value: true },
    });
    let pinsMap: Record<string, string> = {};
    if (pinsSetting?.value) {
      try {
        pinsMap = JSON.parse(pinsSetting.value) as Record<string, string>;
      } catch {
        pinsMap = {};
      }
    }
    pinsMap[username] = pinCode;
    await (this.prisma as any).setting.upsert({
      where: { key: 'staff:plain_pins' },
      update: { value: JSON.stringify(pinsMap) },
      create: { key: 'staff:plain_pins', value: JSON.stringify(pinsMap) },
    });
    try {
      await this.posCallback.updatePosUserPin({ username, pinCode });
    } catch (e) {
      console.warn('[Mobile][Users] POS update pin failed:', (e as Error).message);
    }
    return { username, role: existing.role, isActive: existing.isActive, pinCode };
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
      where: { username: oldUsername },
      select: { id: true, role: true, isActive: true, createdAt: true, updatedAt: true },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }
    const conflict = await (this.prisma as any).staff.findUnique({
      where: { username: newUsername },
      select: { id: true },
    });
    if (conflict) {
      throw new BadRequestException('username already exists');
    }
    const updated = await (this.prisma as any).staff.update({
      where: { username: oldUsername },
      data: { username: newUsername },
      select: { id: true, username: true, role: true, isActive: true, createdAt: true, updatedAt: true },
    });
    const pinsSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'staff:plain_pins' },
      select: { value: true },
    });
    let pinCode = '';
    if (pinsSetting?.value) {
      try {
        const pinsMap = JSON.parse(pinsSetting.value) as Record<string, string>;
        pinCode = pinsMap[oldUsername] ?? '';
        if (pinCode) {
          delete pinsMap[oldUsername];
          pinsMap[newUsername] = pinCode;
          await (this.prisma as any).setting.upsert({
            where: { key: 'staff:plain_pins' },
            update: { value: JSON.stringify(pinsMap) },
            create: { key: 'staff:plain_pins', value: JSON.stringify(pinsMap) },
          });
        }
      } catch {
        // ignore malformed pins map
      }
    }
    try {
      await this.posCallback.renamePosUser({
        oldUsername,
        newUsername,
      });
    } catch (e) {
      console.warn('[Mobile][Users] POS rename user failed:', (e as Error).message);
    }
    return { ...updated, pinCode };
  }

  async deleteUser(usernameParam: string) {
    const username = (usernameParam ?? '').trim();
    const existing = await (this.prisma as any).staff.findUnique({
      where: { username },
      select: { id: true, role: true },
    });
    if (!existing) {
      throw new NotFoundException('User not found');
    }
    if (normalizeStaffRole(existing.role) === StaffRole.MANAGER) {
      const managerCount = await (this.prisma as any).staff.count({
        where: { role: { in: ['ADMIN', 'MANAGER'] }, isActive: true },
      });
      if (managerCount <= 1) {
        throw new BadRequestException('Cannot delete the last manager');
      }
    }
    await (this.prisma as any).staff.delete({ where: { username } });
    const pinsSetting = await (this.prisma as any).setting.findUnique({
      where: { key: 'staff:plain_pins' },
      select: { value: true },
    });
    if (pinsSetting?.value) {
      try {
        const pinsMap = JSON.parse(pinsSetting.value) as Record<string, string>;
        delete pinsMap[username];
        await (this.prisma as any).setting.upsert({
          where: { key: 'staff:plain_pins' },
          update: { value: JSON.stringify(pinsMap) },
          create: { key: 'staff:plain_pins', value: JSON.stringify(pinsMap) },
        });
      } catch {
        // ignore malformed pins map
      }
    }
    try {
      await this.posCallback.deletePosUser({ username });
    } catch (e) {
      console.warn('[Mobile][Users] POS delete user failed:', (e as Error).message);
    }
    return { success: true };
  }
}
