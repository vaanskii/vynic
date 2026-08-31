/**
 * Issues a POS Device credential for one Venue.
 *
 *   npx ts-node -T scripts/issue-device-credential.ts \
 *     --venue <venueId> --name "Vankisi bar terminal" --platform windows
 *
 * TRANSITIONAL, AND DELIBERATELY NOT AN ENDPOINT. Minting a credential is a
 * control-plane action, and the platform-admin authorization boundary that
 * would authorize one does not exist yet (see docs/PLATFORM_CONTROL_PLANE.md).
 * Rather than open an HTTP route nobody can protect, this requires shell access
 * to the server — which is an authorization boundary that already exists, and
 * one that cannot quietly become the SaaS onboarding model, because self-service
 * onboarding cannot be built out of it.
 *
 * The secret is printed once and never stored in plaintext: only its Argon2id
 * verifier reaches the database. There is no way to recover it afterwards —
 * issue a new credential and revoke the old Device instead.
 */
import { PrismaService } from '../src/prisma.service';
import { DeviceCredentialService } from '../src/auth/device-credential.service';
import { randomUUID } from 'node:crypto';

function arg(name: string): string | undefined {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return undefined;
  return process.argv[index + 1];
}

async function main(): Promise<void> {
  const venueId = arg('venue');
  if (!venueId) {
    console.error(
      'Usage: issue-device-credential.ts --venue <venueId> ' +
        '[--name "<display name>"] [--platform windows|macos|linux] ' +
        '[--installation <installationId>]',
    );
    process.exitCode = 1;
    return;
  }

  const prisma = new PrismaService();
  await prisma.$connect();
  try {
    const venue = await prisma.venue.findUnique({
      where: { id: venueId },
      select: { id: true, name: true, status: true },
    });
    if (!venue) {
      console.error(`No venue ${venueId}.`);
      process.exitCode = 1;
      return;
    }

    const issued = await new DeviceCredentialService(prisma).issueCredential({
      venueId: venue.id,
      // The POS writes its own installation id into edge_device.json on first
      // run. Pass it so the Device row matches the machine it was issued for.
      installationId: arg('installation') ?? randomUUID(),
      displayName: arg('name') ?? `POS ${venue.name}`,
      platform: arg('platform') ?? 'windows',
    });

    console.log('');
    console.log(`Venue    ${venue.name} (${venue.id})`);
    console.log(`Device   ${issued.deviceId}`);
    console.log('');
    console.log('Credential — shown once, never recoverable:');
    console.log('');
    console.log(`  ${issued.credential}`);
    console.log('');
    console.log('Install it on that POS by writing exactly that line to');
    console.log('  <POS data directory>/edge_device_provision.txt');
    console.log('then restarting the POS. It is absorbed and the file removed.');
    console.log('Do not leave a copy behind, and do not commit it.');
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

void main();
