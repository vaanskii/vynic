import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { TenantContext } from '../../tenancy/tenant-context';
import type { MenuService } from '../menu/menu.service';
import { bookingCart } from '../reservation/booking-request';

/** Created by server pricing; browser money never enters the provider adapter. */
export interface BookingPaymentIntent {
  readonly amountMinor: number;
  readonly currency: 'GEL';
}

export function bookingAmountInGel(minor: number): number {
  if (!Number.isSafeInteger(minor) || minor < 0)
    throw new BadRequestException('Invalid booking amount');
  const value = new Prisma.Decimal(minor).div(100).toNumber();
  // Existing persistence/provider contracts use a JSON number. Refuse an
  // amount whose decimal JSON representation would lose a minor unit.
  if (!new Prisma.Decimal(value.toString()).mul(100).equals(minor))
    throw new BadRequestException('Booking amount is too large');
  return value;
}

function priceMinor(price: number): bigint {
  if (!Number.isFinite(price) || price < 0)
    throw new BadRequestException('Menu price is unavailable');
  const minor = new Prisma.Decimal(price.toString())
    .mul(100)
    .toDecimalPlaces(0, Prisma.Decimal.ROUND_HALF_UP);
  if (minor.greaterThan(Number.MAX_SAFE_INTEGER))
    throw new BadRequestException('Menu price is too large');
  return BigInt(minor.toFixed(0));
}

function safeMinor(value: bigint): number {
  if (value > BigInt(Number.MAX_SAFE_INTEGER))
    throw new BadRequestException('Booking amount is too large');
  return Number(value);
}

/** One pricing formula for every public booking creation path. */
export async function priceBookingCart(
  menu: MenuService,
  tenant: TenantContext,
  input: unknown,
) {
  const lines = bookingCart(input);
  const menuItems: Array<{
    id: string;
    variantId?: string;
    quantity: number;
    price: number;
    name: string;
    imageUrl: null;
    total: number;
    translations: { en: { name: string }; ka: { name: string } };
  }> = [];
  let subtotalMinor = 0n;
  for (const line of lines) {
    const selected = await menu.getBookableSelection(
      tenant,
      line.id,
      line.variantId,
    );
    const unitMinor = priceMinor(selected.price);
    const lineMinor = unitMinor * BigInt(line.quantity);
    subtotalMinor += lineMinor;
    menuItems.push({
      id: selected.itemId,
      ...(selected.variantId ? { variantId: selected.variantId } : {}),
      quantity: line.quantity,
      price: bookingAmountInGel(safeMinor(unitMinor)),
      total: bookingAmountInGel(safeMinor(lineMinor)),
      name: selected.nameEn,
      imageUrl: null,
      translations: {
        en: { name: selected.nameEn },
        ka: { name: selected.nameKa },
      },
    });
  }
  // Preserve the existing server policy: 10% service, minimum 1 GEL (including
  // table-only bookings). Round half up in minor units, as other money rules do.
  const serviceMinor = (subtotalMinor + 5n) / 10n;
  const sumMinor = subtotalMinor + serviceMinor;
  const amountMinor = safeMinor(sumMinor < 100n ? 100n : sumMinor);
  const payment: BookingPaymentIntent = { amountMinor, currency: 'GEL' };
  return {
    payment,
    menuItems,
    subtotal: bookingAmountInGel(safeMinor(subtotalMinor)),
    serviceFee: bookingAmountInGel(safeMinor(serviceMinor)),
    totalAmount: bookingAmountInGel(amountMinor),
  };
}
