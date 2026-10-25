import 'reflect-metadata';
jest.mock('uuid', () => ({
  v4: () =>
    jest
      .requireActual<typeof import('node:crypto')>('node:crypto')
      .randomUUID(),
}));
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { OwnerInvitationsService } from './owner-invitations.service';
import { MailService, InvitationMail, MailResult } from '../mail/mail.service';
import { OnboardingRequestsService } from './onboarding-requests';
import { onboardingApp } from '../../test/onboarding-app.fixture';
import { isFreshDisposableDatabase } from '../../test/disposable-database';
import type { PlatformPrincipal } from '../platform/platform-auth-context';

const url = process.env.MAIL_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Invitation mail / disposable PostgreSQL',
  () => {
    let db: PrismaService,
      service: OwnerInvitationsService,
      actor: PlatformPrincipal,
      org: string;
    let app: Awaited<ReturnType<typeof onboardingApp>>;
    const send = jest.fn<Promise<MailResult>, [InvitationMail]>();
    beforeAll(async () => {
      if (!isFreshDisposableDatabase(url!))
        throw Error('Fresh disposable loopback database required');
      process.env.JWT_SECRET = 'synthetic-mail-test-signing-key';
      process.env.COOKIE_ENCRYPTION_KEY = 'synthetic-mail-test-cookie-key';
      db = new PrismaService({ datasourceUrl: url });
      await db.$connect();
      const admin = await db.platformUser.create({
        data: {
          email: randomUUID() + '@test.invalid',
          displayName: 'Synthetic admin',
          passwordHash: 'unused',
          role: 'SUPER_ADMIN',
        },
      });
      actor = {
        platformUserId: admin.id,
        role: admin.role,
        email: admin.email,
        displayName: admin.displayName,
      };
      org = (
        await db.organization.create({
          data: { name: 'Synthetic mail organization' },
        })
      ).id;
      app = await onboardingApp(db, undefined, {
        providers: [
          { provide: MailService, useValue: { sendOwnerInvitation: send } },
        ],
      });
      service = app.get(OwnerInvitationsService);
    });
    beforeEach(() => {
      send.mockReset();
      send.mockResolvedValue({
        status: 'accepted',
        diagnostic: 'Mock accepted.',
      });
    });
    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });
    it('sends only committed invitations to the stored recipient', async () => {
      send.mockImplementation(async (message) => {
        // Separate database client cannot see uncommitted invitations.
        const observer = new PrismaService({ datasourceUrl: url });
        try {
          const row = await observer.ownerInvitation.findUniqueOrThrow({
            where: { id: message.id },
          });
          expect(message.email).toBe(row.email);
          expect(row.organizationId).toBe(org);
        } finally {
          await observer.$disconnect();
        }
        return { status: 'accepted', diagnostic: 'Mock accepted.' };
      });
      const result = await service.create(actor, {
        organizationId: org,
        email: 'owner@unit.test',
      });
      expect(result.mail.status).toBe('accepted');
      expect(send).toHaveBeenCalledTimes(1);
    });
    it('never sends when issuance rolls back', async () => {
      await expect(
        db.$transaction(async (tx) => {
          await service.issue(tx, actor, org, 'rollback@unit.test');
          throw Error('rollback');
        }),
      ).rejects.toThrow('rollback');
      expect(send).not.toHaveBeenCalled();
      expect(
        await db.ownerInvitation.count({
          where: { email: 'rollback@unit.test' },
        }),
      ).toBe(0);
    });
    it('preserves committed provisioning on failure and reports disabled mode honestly', async () => {
      send.mockResolvedValue({ status: 'disabled', diagnostic: 'Disabled.' });
      const result = await service.provision(actor, {
        organizationName: 'Synthetic mail provisioning',
        name: 'Synthetic venue',
        email: 'provision@unit.test',
      });
      expect(result).toMatchObject({ mail: { status: 'disabled' } });
      expect(
        await db.venue.findUnique({ where: { id: result.venue.id } }),
      ).not.toBeNull();
      send.mockRejectedValue(Error('sensitive provider response'));
      const next = await service.create(actor, {
        organizationId: org,
        email: 'failure@unit.test',
      });
      expect(next.mail.status).toBe('unknown');
      expect(JSON.stringify(next)).not.toContain('sensitive provider response');
      expect(
        await db.ownerInvitation.findUnique({
          where: { id: next.invitation.id },
        }),
      ).not.toBeNull();
    });
    it('regeneration sends once and invalidates the old token; revocation never sends', async () => {
      const original = await service.create(actor, {
        organizationId: org,
        email: 'regenerate@unit.test',
      });
      send.mockClear();
      const next = await service.change(actor, original.invitation.id, true);
      expect(send).toHaveBeenCalledTimes(1);
      expect((await service.deliverIssued(original)).mail.status).toBe(
        'skipped',
      );
      if (!('invitation' in next)) throw Error('Expected replacement');
      await service.change(actor, next.invitation.id, false);
      expect((await service.deliverIssued(next)).mail.status).toBe('skipped');
      expect(send).toHaveBeenCalledTimes(1);
    });
    it('rejects mismatched organization, recipient, token and unsafe recipient input', async () => {
      const issued = await db.$transaction((tx) =>
        service.issue(tx, actor, org, 'boundary@unit.test'),
      );
      for (const altered of [
        {
          ...issued,
          invitation: { ...issued.invitation, organizationId: randomUUID() },
        },
        {
          ...issued,
          invitation: { ...issued.invitation, email: 'foreign@unit.test' },
        },
        { ...issued, invitationPath: '/invite#token=' + 'x'.repeat(43) },
      ])
        expect((await service.deliverIssued(altered)).mail.status).toBe(
          'skipped',
        );
      await expect(
        service.create(actor, {
          organizationId: org,
          email: 'one@unit.test,two@unit.test',
        }),
      ).rejects.toThrow('Invalid email');
      expect(send).not.toHaveBeenCalled();
    });
    it('approval sends after the outer review commits; repeated review does not send again', async () => {
      const row = await db.onboardingRequest.create({
        data: {
          applicantName: 'Synthetic owner',
          businessName: 'Synthetic business',
          email: 'approval@unit.test',
          phone: '+995555000000',
        },
      });
      const requests = app.get(OnboardingRequestsService);
      send.mockImplementation(async () => {
        expect(
          (
            await db.onboardingRequest.findUniqueOrThrow({
              where: { id: row.id },
            })
          ).status,
        ).toBe('APPROVED');
        return { status: 'accepted', diagnostic: 'Mock accepted.' };
      });
      const result = await requests.review(actor, row.id, {
        status: 'APPROVED',
        outcome: 'NO_PLAN',
      });
      expect(result.prepared?.mail.status).toBe('accepted');
      await expect(
        requests.review(actor, row.id, { status: 'APPROVED' }),
      ).rejects.toThrow('already reviewed');
      expect(send).toHaveBeenCalledTimes(1);
    });
    it('a failure after nested provisioning rolls back the invitation without sending', async () => {
      const row = await db.onboardingRequest.create({
        data: {
          applicantName: 'Synthetic rollback',
          businessName: 'Synthetic rollback',
          email: 'nested-rollback@unit.test',
          phone: '+995555000000',
        },
      });
      await expect(
        app.get(OnboardingRequestsService).review(actor, row.id, {
          status: 'APPROVED',
          outcome: 'TRIAL',
          planId: randomUUID(),
          trialEndsAt: new Date(Date.now() + 86400000).toISOString(),
        }),
      ).rejects.toThrow();
      expect(
        await db.ownerInvitation.count({ where: { email: row.email } }),
      ).toBe(0);
      expect(
        (
          await db.onboardingRequest.findUniqueOrThrow({
            where: { id: row.id },
          })
        ).status,
      ).toBe('PENDING');
      expect(send).not.toHaveBeenCalled();
    });
    it('anonymous recovery only flags review and sends nothing', async () => {
      await service.requestRecovery(
        { email: 'recovery@unit.test' },
        '127.0.0.1',
      );
      expect(send).not.toHaveBeenCalled();
    });
  },
);
