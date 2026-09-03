import { BadRequestException } from '@nestjs/common';

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Bounded list reads. No search engine, just a ceiling nothing can exceed. */
export const DEFAULT_PAGE_SIZE = 50;
export const MAX_PAGE_SIZE = 200;

export interface Page {
  limit: number;
  offset: number;
}

/**
 * Hand-written validation rather than class-validator DTOs.
 *
 * The backend's global ValidationPipe skips plain request bodies, and every
 * existing controller validates its own input, so introducing decorated DTOs
 * here would make the platform module the only one with a different convention.
 * What matters is that nothing untyped reaches Prisma, which these enforce.
 */
export function requireUuid(value: unknown, field: string): string {
  if (typeof value !== 'string' || !UUID_PATTERN.test(value.trim())) {
    throw new BadRequestException(`${field} must be a UUID`);
  }
  return value.trim();
}

export function requireText(
  value: unknown,
  field: string,
  { max = 200, min = 1 }: { max?: number; min?: number } = {},
): string {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < min || text.length > max) {
    throw new BadRequestException(
      `${field} must be between ${min} and ${max} characters`,
    );
  }
  return text;
}

export function optionalText(
  value: unknown,
  field: string,
  options?: { max?: number; min?: number },
): string | undefined {
  if (value === undefined || value === null) return undefined;
  return requireText(value, field, options);
}

export function requireEnumValue<T extends string>(
  value: unknown,
  allowed: readonly T[],
  field: string,
): T {
  const raw = typeof value === 'string' ? value.trim().toUpperCase() : '';
  const match = allowed.find((option) => option === raw);
  if (!match) {
    throw new BadRequestException(
      `${field} must be one of ${allowed.join(', ')}`,
    );
  }
  return match;
}

export function readPage(query: { limit?: string; offset?: string }): Page {
  const limit = parseBounded(query.limit, DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
  const offset = parseBounded(query.offset, 0, Number.MAX_SAFE_INTEGER);
  return { limit, offset };
}

function parseBounded(raw: string | undefined, fallback: number, max: number) {
  if (raw === undefined || raw.trim() === '') return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new BadRequestException('limit and offset must be whole numbers');
  }
  return Math.min(parsed, max);
}
