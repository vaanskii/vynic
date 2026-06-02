/** Canonical staff roles (Prisma [StaffRole] enum). */
export const StaffRole = {
  MANAGER: 'MANAGER',
  SUPERVISOR: 'SUPERVISOR',
  WAITER: 'WAITER',
} as const;

export type StaffRoleValue = (typeof StaffRole)[keyof typeof StaffRole];

/** @deprecated Migrated to MANAGER — still accepted when reading legacy rows/tokens. */
export const LEGACY_ADMIN_ROLE = 'ADMIN';

export const ASSIGNABLE_STAFF_ROLES: StaffRoleValue[] = [
  StaffRole.MANAGER,
  StaffRole.SUPERVISOR,
  StaffRole.WAITER,
];

/** Roles allowed to sign in to the manager mobile app (მენეჯერის აპი — manager only). */
export const MOBILE_APP_STAFF_ROLES: string[] = [
  StaffRole.MANAGER,
  LEGACY_ADMIN_ROLE,
];

export function normalizeStaffRole(raw?: string | null): StaffRoleValue {
  const role = (raw ?? '').trim().toUpperCase();
  if (role === LEGACY_ADMIN_ROLE || role === StaffRole.MANAGER) {
    return StaffRole.MANAGER;
  }
  if (role === StaffRole.SUPERVISOR) return StaffRole.SUPERVISOR;
  return StaffRole.WAITER;
}

export function isMobileAppStaffRole(raw?: string | null): boolean {
  const normalized = (raw ?? '').trim().toUpperCase();
  return MOBILE_APP_STAFF_ROLES.includes(normalized);
}

export function staffRoleLabelKa(raw?: string | null): string {
  switch (normalizeStaffRole(raw)) {
    case StaffRole.MANAGER:
      return 'მენეჯერი';
    case StaffRole.SUPERVISOR:
      return 'სუპერვაიზერი';
    case StaffRole.WAITER:
    default:
      return 'ოფიციანტი';
  }
}

/** Client / POS Hive role string (lowercase). */
export function toClientRole(raw?: string | null): string {
  return normalizeStaffRole(raw).toLowerCase();
}
