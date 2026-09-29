import { BadRequestException } from '@nestjs/common';

// Request-work limits, not restaurant capacity or stock policy. Count units
// across the whole cart so duplicate lines cannot evade the quantity bound.
export const MAX_BOOKING_LINES = 100;
export const MAX_BOOKING_QUANTITY = 1000;

export interface BookingCartLine {
  id: string;
  variantId?: string;
  quantity: number;
}

export interface BookingIntent {
  selectedTables: string[];
  selectedDate: string;
  selectedTime: string;
  menuItems: BookingCartLine[];
  customerName?: string;
  customerEmail?: string;
  customerPhone?: string;
  notes?: string;
  language?: string;
  numberOfGuests?: number;
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new BadRequestException('A booking object is required');
  return value as Record<string, unknown>;
}

function text(value: unknown, field: string, max = 4096): string {
  if (typeof value !== 'string' || value.length > max)
    throw new BadRequestException(`${field} must be a bounded string`);
  return value;
}

function id(value: unknown, field: string): string {
  const result = text(value, field, 200);
  if (!result.trim()) throw new BadRequestException(`${field} is required`);
  return result;
}

/** Runtime validation: no numeric coercion, flooring or fallback quantities. */
export function bookingCart(value: unknown): BookingCartLine[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > MAX_BOOKING_LINES)
    throw new BadRequestException('Invalid booking cart size');
  let units = 0;
  return value.map((raw: unknown) => {
    const line = record(raw);
    if (
      typeof line.quantity !== 'number' ||
      !Number.isSafeInteger(line.quantity) ||
      line.quantity < 1 ||
      line.quantity > MAX_BOOKING_QUANTITY
    )
      throw new BadRequestException('Invalid booking quantity');
    units += line.quantity;
    if (units > MAX_BOOKING_QUANTITY)
      throw new BadRequestException('Booking quantity limit exceeded');
    return {
      id: id(line.id, 'menu item id'),
      ...(line.variantId === undefined
        ? {}
        : { variantId: id(line.variantId, 'variant id') }),
      quantity: line.quantity,
    };
  });
}

/**
 * Both public routes use this runtime DTO at the application boundary.
 * Legacy money/display fields and venueId/userId are deliberately discarded;
 * existing CUSTOM clients may keep sending them, but none is authoritative.
 */
export function bookingIntent(value: unknown): BookingIntent {
  const input = record(value);
  if (!Array.isArray(input.selectedTables) || input.selectedTables.length > 100)
    throw new BadRequestException('selectedTables must be a bounded array');
  const selectedTables = input.selectedTables.map((v: unknown) =>
    id(v, 'table'),
  );
  const selectedDate = text(input.selectedDate, 'selectedDate', 10);
  const selectedTime = text(input.selectedTime, 'selectedTime', 5);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(selectedDate))
    throw new BadRequestException('selectedDate must be YYYY-MM-DD');
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(selectedTime))
    throw new BadRequestException('selectedTime must be HH:mm');
  if (
    input.numberOfGuests !== undefined &&
    (typeof input.numberOfGuests !== 'number' ||
      !Number.isSafeInteger(input.numberOfGuests) ||
      input.numberOfGuests < 1 ||
      input.numberOfGuests > MAX_BOOKING_QUANTITY)
  )
    throw new BadRequestException('Invalid numberOfGuests');
  return {
    selectedTables,
    selectedDate,
    selectedTime,
    menuItems: bookingCart(input.menuItems),
    customerName: optionalText(input.customerName, 'customerName'),
    customerEmail: optionalText(input.customerEmail, 'customerEmail'),
    customerPhone: optionalText(input.customerPhone, 'customerPhone'),
    notes: optionalText(input.notes, 'notes'),
    language: optionalText(input.language, 'language'),
    numberOfGuests: input.numberOfGuests,
  };
}

function optionalText(value: unknown, field: string) {
  return value === undefined ? undefined : text(value, field);
}

export function claimedBookingTotal(value: unknown): unknown {
  return record(value).totalAmount;
}
