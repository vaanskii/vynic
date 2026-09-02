import { randomInt } from 'node:crypto';

/**
 * The one-time code an operator types into a new POS.
 *
 * Crockford base32 — no I, L, O or U — because this is read off a screen and
 * typed on a till by someone who will not be sure whether they saw a zero or an
 * O. The ambiguous characters are not in the alphabet at all, and the ones a
 * human still confuses are mapped on input rather than rejected.
 *
 * Shaped like the Device credential it eventually issues: a public selector
 * that finds the row and a secret that is only ever stored as a verifier. The
 * split exists so a lookup is one indexed read instead of an Argon2 verification
 * against every live enrollment, which would be a denial-of-service surface on
 * an unauthenticated route.
 *
 * ```text
 * 7K2Q - M4XB - 9TFR
 * └──┘   └──────────┘
 * selector   secret      40 bits, single use, minutes to live
 * ```
 */
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
export const ENROLLMENT_SELECTOR_LENGTH = 4;
export const ENROLLMENT_SECRET_LENGTH = 8;
const CODE_LENGTH = ENROLLMENT_SELECTOR_LENGTH + ENROLLMENT_SECRET_LENGTH;

export interface ParsedEnrollmentCode {
  /** Public half. Indexed, stored in the clear, useless on its own. */
  selector: string;
  /** Secret half. Only ever persisted as an Argon2id verifier. */
  secret: string;
  /** The whole normalized code, without separators. */
  normalized: string;
}

/** A fresh code. The caller shows it once and stores only the verifier. */
export function generateEnrollmentCode(): ParsedEnrollmentCode {
  const characters = Array.from(
    { length: CODE_LENGTH },
    () => ALPHABET[randomInt(ALPHABET.length)],
  ).join('');
  return {
    selector: characters.slice(0, ENROLLMENT_SELECTOR_LENGTH),
    secret: characters.slice(ENROLLMENT_SELECTOR_LENGTH),
    normalized: characters,
  };
}

/**
 * Reads what a human typed, or `null` when it cannot be a code at all.
 *
 * Case, spaces and dashes are noise. `I` and `L` become `1` and `O` becomes `0`
 * because that is the mistake people actually make, and refusing it would send
 * an operator back to an administrator over a character that has exactly one
 * sensible reading.
 */
export function parseEnrollmentCode(raw: string): ParsedEnrollmentCode | null {
  const normalized = raw
    .toUpperCase()
    .replace(/[^0-9A-Z]/g, '')
    .replace(/[IL]/g, '1')
    .replace(/O/g, '0');

  if (normalized.length !== CODE_LENGTH) return null;
  for (const character of normalized) {
    if (!ALPHABET.includes(character)) return null;
  }
  return {
    selector: normalized.slice(0, ENROLLMENT_SELECTOR_LENGTH),
    secret: normalized.slice(ENROLLMENT_SELECTOR_LENGTH),
    normalized,
  };
}

/** How the code is shown to the operator: `XXXX-XXXX-XXXX`. */
export function formatEnrollmentCode(normalized: string): string {
  return (normalized.match(/.{1,4}/g) ?? [normalized]).join('-');
}
