import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../../prisma.service';
import { StaffPinVault } from '../../../auth/staff-pin-vault.service';
import { normalizeStaffRole } from '../../../staff/staff-role';
import { pendingStaffUsernames } from '../sync-conflict';
import { StaffSync } from '../sync-payload';
import type { TenantContext } from '../../../auth/pos-auth-context';

/** What one staff snapshot cost, and what it left the server still missing. */
export interface StaffSyncResult {
  /** How many credentials were actually hashed. Zero on a routine snapshot. */
  pinsHashed: number;
  /**
   * Members the snapshot named that the server holds no credential for, so it
   * could not create them. The POS re-sends their PINs on the next snapshot.
   */
  needsPin: string[];
}

/**
 * Mirrors the POS staff list, and reconciles the members it no longer names.
 *
 * A routine snapshot carries usernames and roles but no PINs, so a member the
 * server has never seen cannot be created from one — it is named in
 * [StaffSyncResult.needsPin] rather than given an empty credential. A PIN only
 * arrives for a member the POS has no acknowledgment for, and is hashed for the
 * database and kept in the vault for the manager app.
 *
 * ## Why a supplied PIN is not always hashed
 *
 * bcrypt at cost 12 is deliberately about 200ms, and hashing every supplied PIN
 * in turn made a fourteen-member snapshot spend roughly 2.7 seconds re-deriving
 * hashes the database already held. A PIN equal to the vault entry for a member
 * the server holds cannot change `pinHash`, because every write of `pinHash` in
 * this codebase writes that same plain PIN into the vault — so the derivation is
 * skipped and only role and activity are applied. Anything else — no vault
 * entry, a different PIN, a member with no row — is hashed as before. The
 * comparison decides whether work is redundant, never whether a login succeeds:
 * authentication still verifies the stored hash.
 *
 * This also keeps an older POS build, which sends every PIN on every snapshot,
 * as cheap as a current one instead of holding ingest open for seconds.
 *
 * Reconciliation deactivates payroll-referenced members and deletes other missing
 * members, except those with an
 * in-flight queued mobile change implying they should exist: the POS simply has
 * not applied the create/rename yet, and deleting here would undo it.
 */
@Injectable()
export class StaffSyncService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pinVault: StaffPinVault,
  ) {}

  async sync(
    tenant: TenantContext,
    staff: StaffSync[],
  ): Promise<StaffSyncResult> {
    const plainPinsByUsername = await this.pinVault.read(tenant);
    let pinsMapChanged = false;
    let pinsHashed = 0;
    const needsPin: string[] = [];
    const incomingUsernames = new Set<string>();
    for (const member of staff) {
      incomingUsernames.add(member.username);
      const identity = {
        venueId_username: {
          venueId: tenant.venueId,
          username: member.username,
        },
      };
      const pin = typeof member.pin === 'string' ? member.pin.trim() : '';
      const existingMember = await (this.prisma as any).staff.findUnique({
        where: identity,
      });
      // A PIN that already matches the vault entry for a member the server
      // holds would hash to the credential it already has. Skip the
      // derivation, not the record.
      const credentialUnchanged =
        !!existingMember &&
        pin.length > 0 &&
        plainPinsByUsername[member.username] === pin;

      if (pin.length > 0 && !credentialUnchanged) {
        const pinHash = await bcrypt.hash(pin, 12);
        pinsHashed += 1;
        await (this.prisma as any).staff.upsert({
          where: identity,
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
      } else if (existingMember) {
        await (this.prisma as any).staff.update({
          where: identity,
          data: { role: normalizeStaffRole(member.role), isActive: true },
        });
      } else {
        needsPin.push(member.username);
        console.warn(
          `[SYNC] Skipping new staff "${member.username}" without PIN (the POS re-sends it next snapshot).`,
        );
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
      select: {
        username: true,
        _count: { select: { compensations: true, payrollPeriods: true } },
      },
    });
    const stale = existing
      .map((u: any) => String(u.username ?? ''))
      .filter(
        (username: string) =>
          username.length > 0 &&
          !incomingUsernames.has(username) &&
          !protectedUsernames.has(username),
      );
    // Payroll identities outlive their POS login. Only unreferenced rows are removed.
    const retained = existing.filter(
      (u: any) =>
        stale.includes(u.username) &&
        ((u._count?.compensations ?? 0) > 0 ||
          (u._count?.payrollPeriods ?? 0) > 0),
    );
    for (const member of retained) {
      await this.prisma.staff.update({
        where: {
          venueId_username: {
            venueId: tenant.venueId,
            username: member.username,
          },
        },
        data: { isActive: false },
      });
    }
    const removable = stale.filter(
      (name: string) => !retained.some((u: any) => u.username === name),
    );
    if (removable.length > 0) {
      await (this.prisma as any).staff.deleteMany({
        where: { venueId: tenant.venueId, username: { in: removable } },
      });
    }

    return { pinsHashed, needsPin };
  }
}
