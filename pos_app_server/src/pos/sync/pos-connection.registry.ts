import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma.service';
import { PosCallbackClient } from '../pos-callback.client';
import { isAllowedPosCallbackUrl } from '../pos-callback-url';

/**
 * Where the POS can be reached, and the key it expects on reverse pushes.
 *
 * `PosCallbackClient` holds the address in memory for the transport; this
 * registry owns the durable half — persisting the handshake the POS sends with
 * every snapshot, and restoring it after a server restart so queued mobile
 * edits can still be delivered before the POS pushes again.
 *
 * The SSRF guard lives here rather than in the transport: an address is
 * rejected at the moment it is offered, so a non-LAN address never reaches the
 * database or the in-memory client.
 */
@Injectable()
export class PosConnectionRegistry {
  private static readonly POS_CALLBACK_URL_KEY = 'pos:callback_url';
  private static readonly POS_CONNECTION_KEY_KEY = 'pos:connection_key';

  constructor(
    private readonly prisma: PrismaService,
    private readonly posCallback: PosCallbackClient,
  ) {}

  async restore(): Promise<void> {
    const [urlSetting, keySetting] = await Promise.all([
      (this.prisma as any).setting.findUnique({
        where: { key: PosConnectionRegistry.POS_CALLBACK_URL_KEY },
      }),
      (this.prisma as any).setting.findUnique({
        where: { key: PosConnectionRegistry.POS_CONNECTION_KEY_KEY },
      }),
    ]);
    if (urlSetting?.value) {
      const url = String(urlSetting.value);
      this.posCallback.setCallbackUrl(url);
      console.log(`[Sync] Restored POS callback URL: ${url}`);
    }
    if (keySetting?.value) {
      this.posCallback.setConnectionKey(String(keySetting.value));
    }
  }

  async register(url?: string, key?: string): Promise<void> {
    if (url && url.trim().length > 0) {
      const trimmedUrl = url.trim();
      // SSRF guard: only accept a private/LAN POS address; never persist others.
      if (!isAllowedPosCallbackUrl(trimmedUrl)) {
        console.warn(
          `[Sync] Ignoring POS callback URL (not a private/LAN address): ${trimmedUrl}`,
        );
      } else {
        this.posCallback.setCallbackUrl(trimmedUrl);
        await (this.prisma as any).setting.upsert({
          where: { key: PosConnectionRegistry.POS_CALLBACK_URL_KEY },
          update: { value: trimmedUrl },
          create: {
            key: PosConnectionRegistry.POS_CALLBACK_URL_KEY,
            value: trimmedUrl,
          },
        });
        console.log(`[Sync] POS callback URL registered: ${trimmedUrl}`);
      }
    }
    if (key && key.trim().length > 0) {
      const trimmedKey = key.trim();
      this.posCallback.setConnectionKey(trimmedKey);
      await (this.prisma as any).setting.upsert({
        where: { key: PosConnectionRegistry.POS_CONNECTION_KEY_KEY },
        update: { value: trimmedKey },
        create: {
          key: PosConnectionRegistry.POS_CONNECTION_KEY_KEY,
          value: trimmedKey,
        },
      });
    }
  }

  hasCallbackUrl(): boolean {
    return this.posCallback.hasCallbackUrl();
  }
}
