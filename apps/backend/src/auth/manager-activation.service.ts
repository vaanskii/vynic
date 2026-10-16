import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import {
  createHash,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';
import * as bcrypt from 'bcrypt';
import { Prisma, StaffRole } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { StaffPinVault } from './staff-pin-vault.service';
import { requireManagerSetupIssuer } from './manager-setup-policy';
import { requireCommercialFeature } from '../entitlements/commercial-state';
import { assertStaffPinAvailable } from '../staff/staff-pin-policy';
import { requireText, requireUuid } from '../platform/platform-validation';
import { ControlActor } from '../platform/control-actor';
import type { PosAuthContext } from './pos-auth-context';
import { assertOperationalAuthority } from '../edge/operational-authority';
import {
  EDGE_COMMAND_CONTRACT_VERSION,
  EdgeCommandTypes,
} from '../shared/contracts/edge-command';

const digest = (value: string) =>
  createHash('sha256').update(value).digest('hex');
const managerRoles: StaffRole[] = ['MANAGER', 'ADMIN'];

@Injectable()
export class ManagerActivationService {
  constructor(
    private readonly db: PrismaService,
    private readonly vault: StaffPinVault,
  ) {}

  /** Owner may bootstrap only a restaurant with no Manager history, never recover it. */
  async issue(actor: ControlActor, venueId: string) {
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const venue = await tx.venue.findUnique({ where: { id: venueId } });
      if (!venue) throw new NotFoundException('Restaurant not found');
      if (venue.status !== 'ACTIVE')
        throw new ForbiddenException('Restaurant unavailable');
      if (actor.customerAccountId) {
        const owner = await tx.customerAccount.findFirst({
          where: {
            id: actor.customerAccountId,
            isActive: true,
            memberships: {
              some: { role: 'OWNER', organizationId: venue.organizationId },
            },
          },
        });
        if (!owner) throw new NotFoundException('Restaurant not found');
      } else {
        const admin = await tx.platformUser.findFirst({
          where: {
            id: actor.platformUserId,
            status: 'ACTIVE',
            role: 'SUPER_ADMIN',
          },
        });
        if (!actor.platformUserId || !admin)
          throw new ForbiddenException('Platform administrator required');
      }
      await requireCommercialFeature(tx, venueId, 'POS');
      await requireCommercialFeature(tx, venueId, 'MANAGER_APP');
      if (
        (await tx.managerActivation.findUnique({ where: { venueId } }))
          ?.consumedAt
      )
        throw new ConflictException(
          'Initial activation already completed; contact Vynic Platform Admin',
        );
      if (
        await tx.staff.count({ where: { venueId, role: { in: managerRoles } } })
      )
        throw new ConflictException(
          'Manager already exists; contact Vynic Platform Admin for recovery',
        );
      const secret = randomBytes(32).toString('base64url');
      const expiresAt = new Date(Date.now() + 30 * 60_000);
      const data = {
        secretHash: digest(secret),
        expiresAt,
        issuerId: actor.customerAccountId ?? actor.platformUserId,
        issuerType: actor.customerAccountId ? 'CUSTOMER' : 'PLATFORM',
        setupEnrollmentId: null,
        setupDeviceId: null,
      };
      const row = await tx.managerActivation.upsert({
        where: { venueId },
        create: { venueId, ...data },
        update: { ...data, consumedAt: null, requestId: null, staffId: null },
      });
      await this.audit(tx, data, venueId, 'manager.activation_issued', {
        activationId: row.id,
      });
      // Returned once; reissuing revokes the previous code. Neither code nor PIN is audited.
      return {
        code: `${row.id}.${secret}`,
        expiresAt,
        venueCode: venue.loginCode,
      };
    });
  }

  async complete(auth: PosAuthContext, body: Record<string, unknown>) {
    if (auth.authenticationMode !== 'device' || !auth.deviceId)
      throw new UnauthorizedException('Registered POS required');
    if (!body || typeof body !== 'object' || Array.isArray(body))
      throw new BadRequestException('Activation details are required');
    const code = requireText(body.code, 'Activation code', { max: 100 });
    const [id, secret, extra] = code.split('.');
    if (
      extra ||
      !/^[0-9a-f-]{36}$/.test(id ?? '') ||
      !/^[\w-]{43}$/.test(secret ?? '')
    )
      throw new UnauthorizedException('Activation code unavailable');
    return this.completeGranted(auth, body, { id, secret });
  }

  async completeSetup(auth: PosAuthContext, body: Record<string, unknown>) {
    return this.completeGranted(auth, body);
  }

  private async completeGranted(
    auth: PosAuthContext,
    body: Record<string, unknown>,
    legacy?: { id: string; secret: string },
  ) {
    if (auth.authenticationMode !== 'device' || !auth.deviceId)
      throw new UnauthorizedException('Registered POS required');
    if (!body || typeof body !== 'object' || Array.isArray(body))
      throw new BadRequestException('Activation details are required');
    const requestId = requireUuid(body.requestId, 'requestId');
    const name = requireText(body.name, 'Name', { max: 80 });
    const pin = requireText(body.pin, 'PIN');
    if (!/^\d{4,6}$/.test(pin))
      throw new BadRequestException('PIN must contain 4–6 digits');
    // Device authority resolves the tenant; an invitation alone cannot register Staff.
    return this.db.$transaction(
      async (tx) => {
        await assertOperationalAuthority(tx, auth);
        // Status changes update Device directly. Lock it as well so a concurrent
        // revocation cannot commit between the authority check and registration.
        const devices = await tx.$queryRaw<{ id: string }[]>`
          SELECT "id" FROM "pos"."Device"
          WHERE "id"=${auth.deviceId} AND "venueId"=${auth.venueId} AND "status"='ACTIVE'
          FOR UPDATE`;
        if (!devices.length)
          throw new ForbiddenException('Active POS required');
        const grant = await tx.managerActivation.findUnique({
          where: legacy ? { id: legacy.id } : { venueId: auth.venueId },
          include: {
            venue: true,
            setupEnrollment: {
              select: {
                id: true,
                initialManagerSetup: true,
                deviceId: true,
                redeemedAt: true,
                cancelledAt: true,
                expiresAt: true,
              },
            },
          },
        });
        const nowCheck = new Date();
        const setup = grant?.setupEnrollment;
        const authorized = legacy
          ? grant &&
            !grant.setupEnrollmentId &&
            timingSafeEqual(
              Buffer.from(grant.secretHash, 'hex'),
              Buffer.from(digest(legacy.secret), 'hex'),
            )
          : grant &&
            grant.setupDeviceId === auth.deviceId &&
            setup?.initialManagerSetup &&
            setup.deviceId === auth.deviceId &&
            setup.redeemedAt !== null &&
            setup.cancelledAt === null &&
            setup.expiresAt > nowCheck &&
            body.setupId === grant.id;
        if (
          !grant ||
          !authorized ||
          grant.venueId !== auth.venueId ||
          grant.expiresAt <= nowCheck
        )
          throw new UnauthorizedException('Activation code unavailable');
        await requireCommercialFeature(tx, grant.venueId, 'POS');
        await requireCommercialFeature(tx, grant.venueId, 'MANAGER_APP');
        const venueCode = grant.venue.loginCode;
        if (grant.venue.status !== 'ACTIVE')
          throw new ForbiddenException('Restaurant unavailable');
        const issuerAllowed =
          grant.issuerType === 'CUSTOMER'
            ? await tx.customerAccount.count({
                where: {
                  id: grant.issuerId,
                  isActive: true,
                  memberships: {
                    some: {
                      role: 'OWNER',
                      organizationId: grant.venue.organizationId,
                    },
                  },
                },
              })
            : await tx.platformUser.count({
                where: {
                  id: grant.issuerId,
                  role: 'SUPER_ADMIN',
                  status: 'ACTIVE',
                },
              });
        if (!issuerAllowed)
          throw new UnauthorizedException('Activation code unavailable');
        if (grant.consumedAt) {
          const staff =
            grant.staffId &&
            (await tx.staff.findUnique({ where: { id: grant.staffId } }));
          // A lost response may be retried, but a used invitation never changes credentials.
          if (
            grant.requestId !== requestId ||
            !staff ||
            !staff.isActive ||
            staff.username !== name ||
            staff.updatedAt.getTime() !== grant.consumedAt.getTime() ||
            !(await bcrypt.compare(pin, staff.pinHash))
          )
            throw new ConflictException(
              'Activation already completed; sign in with your PIN',
            );
          return { username: staff.username, venueCode, completed: true };
        }
        if (
          await tx.staff.count({
            where: { venueId: grant.venueId, role: { in: managerRoles } },
          })
        )
          throw new ConflictException('Manager already exists');
        if (
          await tx.staff.findUnique({
            where: {
              venueId_username: { venueId: grant.venueId, username: name },
            },
          })
        )
          throw new ConflictException('Username already exists');
        await assertStaffPinAvailable(tx, grant.venueId, pin);
        const now = new Date();
        const staff = await tx.staff.create({
          data: {
            id: randomUUID(),
            venueId: grant.venueId,
            username: name,
            displayName: name,
            role: 'MANAGER',
            platformManaged: true,
            pinHash: await bcrypt.hash(pin, 12),
            updatedAt: now,
          },
        });
        const map = await this.vault.read({ venueId: grant.venueId }, tx);
        map[name] = pin;
        await this.vault.write(map, { venueId: grant.venueId }, tx);
        await tx.edgeCommand.create({
          data: {
            venueId: grant.venueId,
            idempotencyKey: `manager-activation:${grant.id}`,
            contractVersion: EDGE_COMMAND_CONTRACT_VERSION,
            type: EdgeCommandTypes.STAFF_CREATE,
            payload: {
              username: name,
              pinCode: pin,
              role: 'manager',
              staffId: staff.id,
              platformAction: 'create',
              platformRevision: now.getTime(),
              platformDisplayName: name,
            },
          },
        });
        await tx.managerActivation.update({
          where: { id: grant.id },
          data: { consumedAt: now, requestId, staffId: staff.id },
        });
        await this.audit(
          tx,
          grant,
          grant.venueId,
          'manager.activation_completed',
          { staffId: staff.id },
        );
        return { username: name, venueCode, completed: true };
      },
      { timeout: 15000 },
    );
  }

  /** Only metadata for the authenticated Device; no PIN or invitation secret. */
  async setupStatus(auth: PosAuthContext) {
    if (auth.authenticationMode !== 'device' || !auth.deviceId)
      throw new UnauthorizedException('Registered POS required');
    const grant = await this.db.managerActivation.findUnique({
      where: { venueId: auth.venueId },
      include: {
        setupEnrollment: {
          select: {
            initialManagerSetup: true,
            deviceId: true,
            redeemedAt: true,
            cancelledAt: true,
            expiresAt: true,
          },
        },
      },
    });
    if (!grant?.setupEnrollmentId || grant.setupDeviceId !== auth.deviceId) {
      const exists = await this.db.staff.count({
        where: { venueId: auth.venueId, role: { in: managerRoles } },
      });
      return {
        state: exists
          ? 'EXISTING_MANAGER'
          : grant?.setupEnrollmentId
            ? 'WAITING_PRIMARY'
            : 'LEGACY_INVITATION',
        setupId: null,
      };
    }
    await assertOperationalAuthority(this.db, auth);
    await requireManagerSetupIssuer(
      this.db,
      auth.venueId,
      grant.issuerType === 'CUSTOMER'
        ? { customerAccountId: grant.issuerId }
        : { platformUserId: grant.issuerId },
    );
    const enrollment = grant.setupEnrollment;
    if (
      !enrollment?.initialManagerSetup ||
      enrollment.deviceId !== auth.deviceId ||
      !enrollment.redeemedAt ||
      enrollment.cancelledAt
    )
      return { state: 'UNAVAILABLE', setupId: null };
    if (grant.consumedAt) return { state: 'COMPLETED', setupId: grant.id };
    if (grant.expiresAt <= new Date() || enrollment.expiresAt <= new Date())
      return { state: 'EXPIRED', setupId: null };
    if (
      await this.db.staff.count({
        where: { venueId: auth.venueId, role: { in: managerRoles } },
      })
    )
      return { state: 'EXISTING_MANAGER', setupId: null };
    return { state: 'READY', setupId: grant.id, expiresAt: grant.expiresAt };
  }

  private audit(
    tx: Prisma.TransactionClient,
    issuer: { issuerId: string; issuerType: string },
    venueId: string,
    action: string,
    metadata: Prisma.InputJsonObject,
  ) {
    const target = { action, targetType: 'Venue', targetId: venueId, metadata };
    return issuer.issuerType === 'CUSTOMER'
      ? tx.customerAuditEvent.create({
          data: { ...target, customerAccountId: issuer.issuerId },
        })
      : tx.platformAuditEvent.create({
          data: { ...target, platformUserId: issuer.issuerId },
        });
  }
}
