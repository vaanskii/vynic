import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../../prisma.service';
import { StaffPinVault } from '../../../auth/staff-pin-vault.service';
import { normalizeStaffRole } from '../../../staff/staff-role';
import { pendingStaffUsernames } from '../sync-conflict';
import { StaffSync } from '../sync-payload';
import type { TenantContext } from '../../../auth/pos-auth-context';

/**
 * Mirrors the POS staff list, and reconciles the members it no longer names.
 *
 * A routine snapshot carries usernames and roles but no PINs, so a member the
 * server has never seen cannot be created from one — it is skipped rather than
 * given an empty credential. A PIN only arrives during explicit provisioning,
 * and is hashed for the database and kept in the vault for the manager app.
 *
 * The reconcile deletes members missing from the snapshot, except those with an
 * in-flight queued mobile change implying they should exist: the POS simply has
 * not applied the create/rename yet, and deleting here would undo it.
 */
@Injectable()
export class StaffSyncService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pinVault: StaffPinVault,
  ) {}

  async sync(tenant: TenantContext, staff: StaffSync[]): Promise<void> {
    const plainPinsByUsername = await this.pinVault.read(tenant);
    let pinsMapChanged = false;
    const incomingUsernames = new Set<string>();
    for (const member of staff) {
      incomingUsernames.add(member.username);
      const pin = typeof member.pin === 'string' ? member.pin.trim() : '';
      const hasPin = pin.length > 0;

      if (hasPin) {
        const pinHash = await bcrypt.hash(pin, 12);
        await (this.prisma as any).staff.upsert({
          where: {
            venueId_username: {
              venueId: tenant.venueId,
              username: member.username,
            },
          },
          update: {
            pinHash,
            role: normalizeStaffRole(member.role),
            isActive: true,
          },
          create: {
            venueId: tenant.venueId,
            username: member.username,
            pinHash,
            role: normalizeStaffRole(member.role),
            isActive: true,
          },
        });
        plainPinsByUsername[member.username] = pin;
        pinsMapChanged = true;
      } else {
        const existing = await (this.prisma as any).staff.findUnique({
          where: {
            venueId_username: {
              venueId: tenant.venueId,
              username: member.username,
            },
          },
        });
        if (existing) {
          await (this.prisma as any).staff.update({
            where: {
              venueId_username: {
                venueId: tenant.venueId,
                username: member.username,
              },
            },
            data: { role: normalizeStaffRole(member.role), isActive: true },
          });
        } else {
          console.warn(
            `[SYNC] Skipping new staff "${member.username}" without PIN (use mobile user create).`,
          );
        }
      }
    }
    if (pinsMapChanged) {
      await this.pinVault.write(plainPinsByUsername, tenant);
    }

    // Reconcile deletions: if user disappeared from Windows POS list,
    // remove it from backend too so mobile and Windows stay 1:1.
    //
    // But never delete a user that has an in-flight queued mobile change
    // (create/rename/pin/role): the POS simply hasn't applied it yet, so its
    // current snapshot legitimately predates the user. Deleting here would
    // wrongly remove a manager-created user until the POS catches up.
    const pendingUserRows = await (
      this.prisma as any
    ).posCallbackOutbox.findMany({
      where: {
        venueId: tenant.venueId,
        status: 'pending',
        endpoint: { startsWith: '/mobile-user-' },
      },
      select: { endpoint: true, payload: true },
    });
    const protectedUsernames = pendingStaffUsernames(pendingUserRows);
    const existing = await (this.prisma as any).staff.findMany({
      where: { venueId: tenant.venueId },
      select: { username: true },
    });
    const stale = existing
      .map((u: any) => String(u.username ?? ''))
      .filter(
        (username: string) =>
          username.length > 0 &&
          !incomingUsernames.has(username) &&
          !protectedUsernames.has(username),
      );
    if (stale.length > 0) {
      await (this.prisma as any).staff.deleteMany({
        where: { venueId: tenant.venueId, username: { in: stale } },
      });
    }
  }
}
