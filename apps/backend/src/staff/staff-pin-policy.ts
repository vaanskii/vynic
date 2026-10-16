import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import * as bcrypt from 'bcrypt';

/**
 * All Staff credential writers must hold the Venue row lock until commit.
 * Salted hashes cannot have a useful unique index: compare the proposed PIN
 * against the current active set, including Platform-managed Staff. Username
 * exclusion is scoped to this Venue and permits a member to keep their PIN.
 */
export async function assertStaffPinAvailable(
  db: Prisma.TransactionClient,
  venueId: string,
  pin: string,
  username?: string,
  knownPins: ReadonlyMap<string, string> = new Map(),
) {
  const others = await db.staff.findMany({
    where: {
      venueId,
      isActive: true,
      ...(username ? { username: { not: username } } : {}),
    },
    select: { username: true, pinHash: true },
  });
  for (const other of others) {
    // Sync already hashed/verified these credentials in this locked transaction.
    // Avoid quadratic bcrypt work for a full new staff snapshot. Long legacy
    // inputs still use bcrypt so its 72-byte truncation cannot hide a collision.
    const known = knownPins.get(other.username);
    const matches =
      known !== undefined &&
      Buffer.byteLength(pin) <= 72 &&
      Buffer.byteLength(known) <= 72
        ? pin === known
        : await bcrypt.compare(pin, other.pinHash);
    if (matches) {
      throw new ConflictException('PIN is already in use in this Venue');
    }
  }
}

/** A role/activation change may omit the PIN; never trust a stale vault entry. */
export async function verifiedStoredStaffPin(
  pin: string | undefined,
  pinHash: string,
): Promise<string> {
  if (!pin || !(await bcrypt.compare(pin, pinHash))) {
    throw new BadRequestException(
      'Set a PIN before activating or granting Manager access',
    );
  }
  return pin;
}
