import { MailService } from '../mail/mail.service';
import { OwnerInvitationsService } from './owner-invitations.service';
import { PrismaService } from '../prisma.service';
import { CustomerAuth } from './customer-auth';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';

describe('Invitation applicant name reuse', () => {
  const row = {
    id: 'invitation',
    organizationId: 'organization',
    email: 'owner@test.invalid',
    expiresAt: new Date(Date.now() + 86400000),
    acceptedAt: null,
    revokedAt: null,
    organization: { name: 'Restaurant' },
  };
  function setup(applicantName: string | null) {
    const db = {
      invitationResumeSession: { deleteMany: jest.fn() },
      ownerInvitation: {
        findUnique: jest.fn().mockResolvedValue(row),
        update: jest.fn(),
      },
      venue: {
        findMany: jest.fn().mockResolvedValue([{ id: 'venue' }]),
        findFirst: jest.fn().mockResolvedValue({ id: 'venue' }),
      },
      onboardingRequest: {
        findFirst: jest
          .fn()
          .mockResolvedValue(applicantName ? { applicantName } : null),
      },
      customerAccount: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest
          .fn()
          .mockImplementation(({ data }) => ({ id: 'account', ...data })),
      },
      organizationMembership: { upsert: jest.fn() },
      customerAuditEvent: { create: jest.fn() },
      $queryRaw: jest.fn(),
      $transaction: jest.fn(),
    };
    db.$transaction.mockImplementation((run) => run(db));
    const service = new OwnerInvitationsService(
      db as unknown as PrismaService,
      { session: jest.fn().mockResolvedValue({}) } as unknown as CustomerAuth,
      { consume: () => true } as unknown as EnrollmentRateLimiter,
      disabledMail,
    );
    return { db, service };
  }
  const token = 'a'.repeat(43);
  it('looks up the personal name within the invited organization and email', async () => {
    const { db, service } = setup('Nino');
    expect(await service.inspect({ token }, 'test')).toMatchObject({
      displayName: 'Nino',
      organizationName: 'Restaurant',
    });
    expect(db.onboardingRequest.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          email: row.email,
          status: 'APPROVED',
          requestedVenueId: null,
          approvedVenueId: { in: ['venue'] },
        },
      }),
    );
  });
  it('registers without a repeated name using the saved applicant name', async () => {
    const { db, service } = setup('Nino');
    await service.accept({ token, password: 'Strong password 123' }, 'test');
    expect(db.customerAccount.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ displayName: 'Nino' }),
    });
  });
  it('still collects a name for manual invitations without an approved request', async () => {
    const { db, service } = setup(null);
    await service.accept(
      { token, displayName: 'Giorgi', password: 'Strong password 123' },
      'test',
    );
    expect(db.customerAccount.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ displayName: 'Giorgi' }),
    });
  });
});

const disabledMail = {
  sendOwnerInvitation: async () => ({
    status: 'disabled',
    diagnostic: 'Test sender disabled.',
  }),
} as unknown as MailService;
