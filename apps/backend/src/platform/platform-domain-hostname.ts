import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { normalizeHostname } from '../website/tenancy/website-host';
import {
  isSaasNamespace,
  saasBaseDomain,
  saasNameTaken,
} from '../website/provisioning/hostname';

/** Only deployment-owned origins are protected; restaurant names are admin-owned. */
export function platformHostname(raw: string): string {
  const hostname = normalizeHostname(raw);
  if (!hostname || hostname.split('.').some((label) => label.length > 63))
    throw new BadRequestException('hostname is not a valid host');
  if (isSaasNamespace(hostname)) {
    const base = saasBaseDomain();
    if (
      hostname === base ||
      ['api', 'admin', 'preview', 'www'].some(
        (label) => hostname === `${label}.${base}`,
      )
    )
      throw new BadRequestException(
        'This hostname serves the Vynic platform. Choose a restaurant hostname.',
      );
  }
  return hostname;
}

export function platformSaasLabel(hostname: string): string | null {
  if (!isSaasNamespace(hostname)) return null;
  const label = hostname.slice(0, -(saasBaseDomain().length + 1));
  return label && !label.includes('.') ? label : null;
}

/** Includes retained assigned identities whose domain row has not been restored. */
export async function assertPlatformHostnameAvailable(
  tx: Prisma.TransactionClient,
  venueId: string,
  hostname: string,
) {
  const label = platformSaasLabel(hostname);
  const domain = await tx.venueDomain.findUnique({ where: { hostname } });
  if (
    (domain && domain.venueId !== venueId) ||
    (label && (await saasNameTaken(tx, label, hostname, venueId)))
  )
    throw new ConflictException(`${hostname} is already assigned to a venue`);
}
