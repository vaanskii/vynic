import { Injectable } from '@nestjs/common';
import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  scryptSync,
} from 'crypto';
import { PrismaService } from '../prisma.service';
import { requireEnv } from '../shared/require-env';
import { BOOTSTRAP_VENUE_ID } from './legacy-pos-tenant.service';
import type { TenantContext } from './pos-auth-context';

type PinMap = Record<string, string>;

/**
 * Encrypted-at-rest store for the staff plain-PIN map (`staff:plain_pins`).
 *
 * Managers (and the Windows POS) are allowed to view/set PINs, which requires
 * recoverable storage — so instead of cleartext, the map is encrypted with
 * AES-256-GCM before it touches the DB. The key is derived from
 * COOKIE_ENCRYPTION_KEY with a distinct salt (key separation from cookies).
 *
 * Backward compatible: legacy cleartext-JSON rows are read transparently and
 * re-encrypted on the next write. Single source of truth for both the mobile
 * users service and the POS staff sync.
 */
@Injectable()
export class StaffPinVault {
  private static readonly SETTING_KEY = 'staff:plain_pins';
  private static readonly PREFIX = 'v1:';
  private readonly algorithm = 'aes-256-gcm';
  private readonly key: Buffer;

  constructor(private readonly prisma: PrismaService) {
    this.key = scryptSync(
      requireEnv('COOKIE_ENCRYPTION_KEY'),
      'staff-pin-vault',
      32,
    );
  }

  /** Decrypt + parse the stored PIN map (handles legacy cleartext rows). */
  async read(tenant?: Pick<TenantContext, 'venueId'>): Promise<PinMap> {
    const venueId = tenant?.venueId ?? BOOTSTRAP_VENUE_ID;
    const row = await (this.prisma as any).setting.findUnique({
      where: {
        venueId_key: { venueId, key: StaffPinVault.SETTING_KEY },
      },
      select: { value: true },
    });
    const stored: unknown = row?.value;
    if (typeof stored !== 'string' || stored.length === 0) return {};
    // Encrypted (v1:) → decrypt; otherwise treat as legacy cleartext JSON.
    const json = stored.startsWith(StaffPinVault.PREFIX)
      ? (this.decrypt(stored) ?? '{}')
      : stored;
    try {
      return JSON.parse(json) as PinMap;
    } catch {
      return {};
    }
  }

  /** Encrypt + persist the PIN map. */
  async write(
    map: PinMap,
    tenant?: Pick<TenantContext, 'venueId'>,
  ): Promise<void> {
    const venueId = tenant?.venueId ?? BOOTSTRAP_VENUE_ID;
    const value = this.encrypt(JSON.stringify(map));
    await (this.prisma as any).setting.upsert({
      where: {
        venueId_key: { venueId, key: StaffPinVault.SETTING_KEY },
      },
      update: { value },
      create: { venueId, key: StaffPinVault.SETTING_KEY, value },
    });
  }

  private encrypt(text: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv(this.algorithm, this.key, iv);
    const enc = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return `${StaffPinVault.PREFIX}${iv.toString('hex')}:${tag.toString('hex')}:${enc.toString('hex')}`;
  }

  private decrypt(stored: string): string | null {
    try {
      const [, ivHex, tagHex, dataHex] = stored.split(':');
      const decipher = createDecipheriv(
        this.algorithm,
        this.key,
        Buffer.from(ivHex, 'hex'),
      );
      decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
      return Buffer.concat([
        decipher.update(Buffer.from(dataHex, 'hex')),
        decipher.final(),
      ]).toString('utf8');
    } catch {
      return null;
    }
  }
}
