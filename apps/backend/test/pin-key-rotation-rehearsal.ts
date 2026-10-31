// Design proof only: pure transformation, no Prisma, environment lookup, logging,
// files or command-line entrypoint. Production transaction/backup tooling is NOT implemented.
import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  scryptSync,
} from 'node:crypto';

export interface PinCiphertextRow {
  venueId: string;
  ciphertext: string;
}
export interface PinRekeyPlan extends PinCiphertextRow {
  replacement: string;
}

export function rehearsePinRekey(
  rows: PinCiphertextRow[],
  oldSecret: string,
  newSecret: string,
): PinRekeyPlan[] {
  if (oldSecret.length < 32 || newSecret.length < 32 || oldSecret === newSecret)
    throw new Error('Rekey requires distinct strong keys');
  const oldKey = scryptSync(oldSecret, 'staff-pin-vault', 32);
  const newKey = scryptSync(newSecret, 'staff-pin-vault', 32);
  const seen = new Set<string>();
  try {
    return rows.map(({ venueId, ciphertext }) => {
      if (!venueId.trim() || seen.has(venueId))
        throw new Error('Invalid or duplicate Venue row');
      seen.add(venueId);
      // No legacy/plaintext/corrupt row may be silently replaced with an empty map.
      if (!/^v1:[a-f0-9]{24}:[a-f0-9]{32}:(?:[a-f0-9]{2})+$/.test(ciphertext))
        throw new Error('Unsupported PIN ciphertext; stop without writes');
      let plain: Buffer | undefined;
      try {
        const [, iv, tag, data] = ciphertext.split(':');
        const decipher = createDecipheriv(
          'aes-256-gcm',
          oldKey,
          Buffer.from(iv, 'hex'),
        );
        decipher.setAuthTag(Buffer.from(tag, 'hex'));
        plain = Buffer.concat([
          decipher.update(Buffer.from(data, 'hex')),
          decipher.final(),
        ]);
        const map: unknown = JSON.parse(plain.toString('utf8'));
        if (
          !map ||
          Array.isArray(map) ||
          typeof map !== 'object' ||
          Object.values(map).some((value) => typeof value !== 'string')
        )
          throw new Error();
        const nonce = randomBytes(12);
        const cipher = createCipheriv('aes-256-gcm', newKey, nonce);
        const enc = Buffer.concat([cipher.update(plain), cipher.final()]);
        const replacement = `v1:${nonce.toString('hex')}:${cipher.getAuthTag().toString('hex')}:${enc.toString('hex')}`;
        // Independent authenticated readback before the caller receives any plan.
        const verify = createDecipheriv('aes-256-gcm', newKey, nonce);
        verify.setAuthTag(cipher.getAuthTag());
        const checked = Buffer.concat([verify.update(enc), verify.final()]);
        const same = checked.equals(plain);
        checked.fill(0);
        if (!same) throw new Error();
        return { venueId, ciphertext, replacement };
      } catch {
        throw new Error('PIN rekey validation failed; stop without writes');
      } finally {
        plain?.fill(0);
      }
    });
  } finally {
    oldKey.fill(0);
    newKey.fill(0);
  }
}
