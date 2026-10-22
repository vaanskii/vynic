import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import type { Tx } from './finance-common';
import { entryId, inputObject, note } from './finance-rules';

export interface CorrectionInput {
  id: string;
  reason: string;
}
export function correctionInput(input: CorrectionInput) {
  inputObject(input);
  if (Object.keys(input).some((key) => key !== 'id' && key !== 'reason'))
    throw new BadRequestException(
      'კორექტირება მოითხოვს მხოლოდ id და reason ველებს',
    );
  const reason = note(input.reason);
  if (!reason) throw new BadRequestException('კორექტირების მიზეზი აუცილებელია');
  return { id: entryId(input.id), reason };
}
export function assertCorrectionReplay(
  row: { venueId: string; reversalOfId: string | null; notes: string | null },
  venueId: string,
  originalId: string,
  reason: string,
  sameParent: boolean,
) {
  if (
    row.venueId !== venueId ||
    row.reversalOfId !== originalId ||
    row.notes !== reason ||
    !sameParent
  )
    throw new ConflictException(
      'კორექტირების იდენტიფიკატორი უკვე გამოყენებულია',
    );
}
export function assertOriginal(row: {
  amount: Prisma.Decimal;
  reversalOfId: string | null;
}) {
  if (row.reversalOfId || row.amount.lte(0))
    throw new ConflictException('კორექტირების ჩანაწერი ხელახლა ვერ გაუქმდება');
}
export async function correctionTransaction<T>(
  db: PrismaService,
  work: (tx: Tx) => Promise<T>,
) {
  try {
    return await db.$transaction(work);
  } catch (error) {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2002'
    )
      throw new ConflictException(
        'კორექტირების იდენტიფიკატორი ან საწყისი ჩანაწერი უკვე გამოყენებულია',
      );
    throw error;
  }
}
export function presentCorrections<
  T extends {
    id: string;
    amount: Prisma.Decimal;
    reversalOfId: string | null;
  },
>(rows: T[], consumedReserve = false) {
  const links = new Map(
    rows.filter((r) => r.reversalOfId).map((r) => [r.reversalOfId, r.id]),
  );
  return rows.map((row) => ({
    ...row,
    amount: row.amount.toFixed(2),
    reversedById: links.get(row.id) ?? null,
    canReverse:
      !row.reversalOfId &&
      row.amount.gt(0) &&
      !links.has(row.id) &&
      !consumedReserve,
    correctionBlockedReason:
      consumedReserve && !row.reversalOfId && !links.has(row.id)
        ? 'ამ ციკლის რეზერვი გამოყენებულია. ჯერ შესაბამისი გადახდები გაასწორეთ.'
        : null,
  }));
}
