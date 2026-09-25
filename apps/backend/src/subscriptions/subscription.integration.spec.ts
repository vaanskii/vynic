import 'reflect-metadata';
jest.mock('uuid', () => ({ v4: () => require('node:crypto').randomUUID() }));
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { SubscriptionService } from './subscription.service';
import {
  commercialState,
  requireCommercialFeature,
} from '../entitlements/commercial-state';
import { CommercialLifecycleService } from '../entitlements/commercial-lifecycle.service';
import { PlatformCommercialService } from '../platform/platform-commercial.service';
import { StaffPinVault } from '../auth/staff-pin-vault.service';
import { OnboardingRequestsService } from '../customer/onboarding-requests';
import { OwnerInvitationsService } from '../customer/owner-invitations.service';
import { CustomerAuth } from '../customer/customer-auth';
import { CustomerService } from '../customer/customer.service';
import { VenueEntitlementsService } from '../entitlements/venue-entitlements.service';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { JwtService } from '@nestjs/jwt';

const url = process.env.COMMERCIAL_TEST_DATABASE_URL;
(url ? describe : describe.skip)(
  'Subscription lifecycle — disposable PostgreSQL',
  () => {
    let db: PrismaService,
      service: SubscriptionService,
      operator: any,
      owner: any,
      requests: OnboardingRequestsService,
      invitations: OwnerInvitationsService;
    let website: any, full: any, pos: any, manager: any, org: any;
    const at = (value: string) => new Date(`${value}T12:00:00Z`);
    const start = at('2027-09-25'),
      middle = at('2027-10-10'),
      renewal = at('2027-10-25');
    beforeAll(async () => {
      const target = new URL(url!);
      if (
        target.hostname !== '127.0.0.1' ||
        target.port !== '55437' ||
        target.pathname !== '/vynic_commercial_test'
      )
        throw Error('Disposable database only');
      process.env.JWT_SECRET = 'lifecycle-test-only';
      db = new PrismaService({ datasourceUrl: url });
      service = new SubscriptionService(db);
      const user = await db.platformUser.create({
        data: {
          email: `${randomUUID()}@test.invalid`,
          displayName: 'Lifecycle operator',
          passwordHash: 'unused',
        },
      });
      operator = { platformUserId: user.id, role: 'SUPER_ADMIN' };
      org = await db.organization.create({ data: { name: 'Lifecycle' } });
      const account = await db.customerAccount.create({
        data: {
          email: `${randomUUID()}@test.invalid`,
          displayName: 'Owner',
          passwordHash: 'unused',
          memberships: { create: { organizationId: org.id } },
        },
      });
      owner = { customerAccountId: account.id };
      const createPlan = async (name: string, price: number, keys: string[]) =>
        db.plan.create({
          data: {
            key: randomUUID(),
            name,
            priceMinor: price,
            features: {
              create: keys.map((key) => ({ feature: { connect: { key } } })),
            },
          },
        });
      website = await createPlan('Website', 5000, ['WEBSITE']);
      full = await createPlan('Full', 15000, ['WEBSITE', 'POS', 'MANAGER_APP']);
      pos = await createPlan('POS', 5000, ['POS']);
      manager = await createPlan('Manager', 5000, ['MANAGER_APP']);
      const limiter = new EnrollmentRateLimiter(),
        commercial = new PlatformCommercialService(db, new StaffPinVault(db));
      const auth = new CustomerAuth(db, new JwtService(), limiter);
      invitations = new OwnerInvitationsService(db, auth, limiter);
      const owners = new CustomerService(
        db,
        new VenueEntitlementsService(db),
        commercial,
        {} as any,
      );
      requests = new OnboardingRequestsService(
        db,
        limiter,
        invitations,
        owners,
        commercial,
      );
    });
    afterAll(async () => {
      await db?.$disconnect();
    });
    const venue = () =>
      db.venue.create({
        data: {
          organizationId: org.id,
          name: 'Lifecycle venue',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          subscription: { create: { status: 'NO_PLAN' } },
        },
      });
    const action = (id: string, action: string, extra = {}, now = middle) =>
      service.action(
        operator,
        id,
        { action, reason: 'Test operator reason', ...extra },
        undefined,
        now,
      );
    const pay = async (id: string, plan: any, now = start) => {
      const quote: any = await service.quote(
        operator,
        id,
        { planId: plan.id },
        now,
      );
      await service.applyTrustedResult(
        {
          provider: 'TEST',
          eventId: randomUUID(),
          operationId: quote.id,
          type:
            quote.kind === 'RENEWAL'
              ? 'renewal_succeeded'
              : 'payment_succeeded',
          amountMinor: quote.amountMinor,
          currency: quote.currency,
        },
        undefined,
        undefined,
        now,
      );
      return quote;
    };
    const state = (id: string, now = middle) => commercialState(db, id, now);
    it('approves the original public request with Trial atomically; acceptance does not reset it; rejects a second trial', async () => {
      const email = `${randomUUID()}@test.invalid`;
      await requests.submit(
        {
          email,
          businessName: 'Trial cafe',
          applicantName: 'Owner',
          phone: '555',
        },
        email,
      );
      const row = await db.onboardingRequest.findFirstOrThrow({
        where: { email },
      });
      const result = await requests.review(operator, row.id, {
        status: 'APPROVED',
        outcome: 'TRIAL',
        planId: website.id,
        trialEndsAt: new Date(Date.now() + 86400000).toISOString(),
      });
      const id = result.prepared!.venue.id;
      expect((await state(id, new Date())).features).toEqual(['WEBSITE']);
      const accepted = await invitations.accept(
        {
          token: result.prepared!.invitationPath.split('=')[1],
          displayName: 'Owner',
          password: 'lifecycle-test-password',
        },
        email,
      );
      expect((await state(id, new Date())).venue.subscription?.status).toBe(
        'TRIAL',
      );
      await expect(
        requests.requestTrial(
          { customerAccountId: accepted.account.id },
          id,
          {},
        ),
      ).rejects.toThrow('already has commercial access');
      await expect(
        requests.review(operator, row.id, {
          status: 'APPROVED',
          outcome: 'NO_PLAN',
        }),
      ).rejects.toThrow('already reviewed');
    });
    it('NO_PLAN approval is separate and invalid Trial rolls back its shell, invitation and approval', async () => {
      const email = `${randomUUID()}@test.invalid`;
      await requests.submit(
        {
          email,
          businessName: 'No plan cafe',
          applicantName: 'Owner',
          phone: '555',
        },
        email,
      );
      const row = await db.onboardingRequest.findFirstOrThrow({
        where: { email },
      });
      const before = await db.venue.count();
      await expect(
        requests.review(operator, row.id, {
          status: 'APPROVED',
          outcome: 'TRIAL',
          planId: website.id,
          trialEndsAt: '2020-01-01',
        }),
      ).rejects.toThrow();
      expect(await db.venue.count()).toBe(before);
      expect(
        (
          await db.onboardingRequest.findUniqueOrThrow({
            where: { id: row.id },
          })
        ).status,
      ).toBe('PENDING');
      const result = await requests.review(operator, row.id, {
        status: 'APPROVED',
        outcome: 'NO_PLAN',
      });
      expect((await state(result.prepared!.venue.id)).allowed).toBe(false);
      await expect(
        requireCommercialFeature(db, result.prepared!.venue.id, 'WEBSITE'),
      ).rejects.toThrow();
    });
    it('expires Trials immediately, reconciles once, extends/resumes and changes Trial plan explicitly', async () => {
      const v = await venue();
      await action(
        v.id,
        'TRIAL',
        { planId: website.id, trialEndsAt: renewal.toISOString() },
        start,
      );
      expect((await state(v.id, renewal)).allowed).toBe(false);
      const lifecycle = new CommercialLifecycleService(db);
      await lifecycle.reconcile(v.id, renewal);
      await lifecycle.reconcile(v.id, renewal);
      expect(
        await db.platformAuditEvent.count({
          where: { targetId: v.id, action: 'venue.trial_expired' },
        }),
      ).toBe(1);
      await expect(action(v.id, 'RESUME', {}, renewal)).rejects.toThrow(
        'Extend',
      );
      await action(
        v.id,
        'TRIAL',
        { planId: full.id, trialEndsAt: at('2027-11-10').toISOString() },
        renewal,
      );
      expect((await state(v.id, renewal)).features).toContain('POS');
    });
    it('first purchase anchors Sep 25 to Oct 25; Trial conversion anchors successful Sep 30 purchase', async () => {
      const v = await venue();
      await pay(v.id, website);
      const s = (await state(v.id)).venue.subscription!;
      expect(s.currentPeriodStart).toEqual(start);
      expect(s.currentPeriodEndsAt).toEqual(renewal);
      expect(s.billingAnchorAt).toEqual(start);
      const trial = await venue();
      await action(
        trial.id,
        'TRIAL',
        { planId: website.id, trialEndsAt: at('2027-10-08').toISOString() },
        start,
      );
      await pay(trial.id, full, at('2027-09-30'));
      const converted = (await state(trial.id)).venue.subscription!;
      expect(converted.status).toBe('ACTIVE');
      expect(converted.trialEndedAt).toEqual(at('2027-09-30'));
      expect(converted.currentPeriodEndsAt).toEqual(at('2027-10-30'));
    });
    it('immediate upgrade costs 5000 minor, retains renewal and rejects replay/different amount/stale success', async () => {
      const v = await venue();
      await pay(v.id, website);
      const q: any = await service.quote(
        owner,
        v.id,
        { planId: full.id },
        middle,
      );
      expect(q.amountMinor).toBe(5000);
      expect((await state(v.id)).features).not.toContain('POS');
      const event = {
        provider: 'TEST',
        eventId: randomUUID(),
        operationId: q.id,
        type: 'payment_succeeded' as const,
        amountMinor: 5000,
        currency: 'GEL',
      };
      await expect(
        service.applyTrustedResult(
          { ...event, amountMinor: 1 },
          undefined,
          undefined,
          middle,
        ),
      ).rejects.toThrow('match');
      await service.applyTrustedResult(event, undefined, undefined, middle);
      await service.applyTrustedResult(event, undefined, undefined, middle);
      const s = await state(v.id);
      expect(s.features).toContain('POS');
      expect(s.venue.subscription?.currentPeriodEndsAt).toEqual(renewal);
      expect(
        await db.subscriptionBillingEvent.count({
          where: { eventId: event.eventId },
        }),
      ).toBe(1);
      const other = await venue();
      await pay(other.id, website);
      const stale: any = await service.quote(
        owner,
        other.id,
        { planId: full.id },
        middle,
      );
      await action(other.id, 'SUSPEND');
      await expect(
        service.applyTrustedResult(
          { ...event, eventId: randomUUID(), operationId: stale.id },
          undefined,
          undefined,
          middle,
        ),
      ).rejects.toThrow('Stale');
      expect((await state(other.id)).features).toEqual([]);
    });
    it('downgrade retains paid features; cancellation of pending change; switches and charges lower price at renewal', async () => {
      const v = await venue();
      await pay(v.id, full);
      await action(v.id, 'SCHEDULE_CHANGE', { planId: website.id });
      expect((await state(v.id)).features).toContain('POS');
      await service.action(
        owner,
        v.id,
        { action: 'CANCEL_CHANGE' },
        undefined,
        middle,
      );
      expect((await state(v.id)).venue.subscription?.pendingPlanId).toBeNull();
      await action(v.id, 'SCHEDULE_CHANGE', { planId: website.id });
      const q = await pay(v.id, website, renewal);
      expect(q.kind).toBe('RENEWAL');
      expect(q.amountMinor).toBe(5000);
      const s = await state(v.id, renewal);
      expect(s.features).toEqual(['WEBSITE']);
      expect(s.venue.subscription?.billingAnchorAt).toEqual(start);
      expect(s.venue.subscription?.currentPeriodEndsAt).toEqual(
        at('2027-11-25'),
      );
    });
    it('cancellation keeps paid features, can be undone, then expires without deleting history or data', async () => {
      const v = await venue();
      await pay(v.id, full);
      await action(v.id, 'SCHEDULE_CANCEL');
      expect((await state(v.id)).features).toContain('POS');
      await action(v.id, 'UNDO_CANCEL');
      expect((await state(v.id)).venue.subscription?.cancelAtPeriodEnd).toBe(
        false,
      );
      await action(v.id, 'SCHEDULE_CANCEL');
      expect((await state(v.id, renewal)).allowed).toBe(false);
      await new CommercialLifecycleService(db).reconcile(v.id, renewal);
      expect((await state(v.id, renewal)).venue.subscription?.status).toBe(
        'CANCELLED',
      );
      expect(await db.venue.count({ where: { id: v.id } })).toBe(1);
      expect(
        await db.venuePlanAssignment.count({ where: { venueId: v.id } }),
      ).toBe(1);
      expect(
        await db.subscriptionBillingEvent.count({
          where: { operation: { venueId: v.id } },
        }),
      ).toBe(1);
    });
    it('suspend/resume requires operator and reason, preserves agreement; immediate cancellation requires confirmation', async () => {
      const v = await venue();
      await pay(v.id, full);
      await expect(
        service.action(owner, v.id, { action: 'SUSPEND' }, undefined, middle),
      ).rejects.toThrow('Operator');
      await expect(
        service.action(
          operator,
          v.id,
          { action: 'SUSPEND' },
          undefined,
          middle,
        ),
      ).rejects.toThrow();
      await action(v.id, 'SUSPEND');
      expect((await state(v.id)).features).toEqual([]);
      await action(v.id, 'RESUME');
      expect((await state(v.id)).features).toContain('POS');
      await expect(action(v.id, 'CANCEL_NOW')).rejects.toThrow('Confirm');
      await action(v.id, 'CANCEL_NOW', { confirm: true });
      expect((await state(v.id)).features).toEqual([]);
    });
    it('list-price edits and pending-price edits do not rewrite agreements', async () => {
      const v = await venue();
      await pay(v.id, full);
      await action(v.id, 'SCHEDULE_CHANGE', { planId: website.id });
      await db.plan.update({
        where: { id: website.id },
        data: { priceMinor: 6000 },
      });
      expect((await state(v.id)).venue.planAssignment?.agreedPriceMinor).toBe(
        15000,
      );
      const q = await pay(v.id, website, renewal);
      expect(q.amountMinor).toBe(5000);
      await db.plan.update({
        where: { id: website.id },
        data: { priceMinor: 5000 },
      });
    });
    it('product combinations and NON_FISCAL_CLOSE remain independent across changes', async () => {
      for (const [plan, expected] of [
        [website, ['WEBSITE']],
        [pos, ['POS']],
        [manager, ['MANAGER_APP']],
      ] as const) {
        const v = await venue();
        await pay(v.id, plan);
        expect((await state(v.id)).features).toEqual(expected);
      }
      const v = await venue();
      await pay(v.id, website);
      const feature = await db.feature.findUniqueOrThrow({
        where: { key: 'NON_FISCAL_CLOSE' },
      });
      await db.venueFeatureOverride.create({
        data: { venueId: v.id, featureId: feature.id, effect: 'ENABLED' },
      });
      await pay(v.id, full, middle);
      expect((await state(v.id)).features).toContain('NON_FISCAL_CLOSE');
      await action(v.id, 'SCHEDULE_CHANGE', { planId: website.id });
      await pay(v.id, website, renewal);
      expect((await state(v.id, renewal)).features).toContain(
        'NON_FISCAL_CLOSE',
      );
    });
    it('owner isolation, duplicate Trial approval, failed payment and unpaid renewal fail closed', async () => {
      const otherOrg = await db.organization.create({
        data: { name: 'Other' },
      });
      const foreign = await db.venue.create({
        data: {
          organizationId: otherOrg.id,
          name: 'Foreign',
          timezone: 'Asia/Tbilisi',
          currency: 'GEL',
          subscription: { create: {} },
        },
      });
      await expect(service.snapshot(foreign.id, owner)).rejects.toThrow(
        'Owner',
      );
      await expect(
        service.quote(owner, foreign.id, { planId: full.id }, start),
      ).rejects.toThrow('Owner');
      const v = await venue();
      const q: any = await service.quote(
        owner,
        v.id,
        { planId: full.id },
        start,
      );
      await service.applyTrustedResult(
        {
          provider: 'TEST',
          eventId: randomUUID(),
          operationId: q.id,
          type: 'payment_failed',
          amountMinor: q.amountMinor,
          currency: q.currency,
        },
        undefined,
        undefined,
        start,
      );
      expect((await state(v.id)).allowed).toBe(false);
      await pay(v.id, website);
      expect((await state(v.id, renewal)).allowed).toBe(false);
      await new CommercialLifecycleService(db).reconcile(v.id, renewal);
      expect((await state(v.id, renewal)).venue.subscription?.status).toBe(
        'PAST_DUE',
      );
    });
    it('concurrent successes settle once; expired quotes and excessive refunds cannot mutate access', async () => {
      const v = await venue();
      const q: any = await service.quote(
        owner,
        v.id,
        { planId: website.id },
        start,
      );
      const event = {
        provider: 'TEST',
        eventId: randomUUID(),
        operationId: q.id,
        type: 'payment_succeeded' as const,
        amountMinor: q.amountMinor,
        currency: q.currency,
      };
      const results = await Promise.allSettled([
        service.applyTrustedResult(event, undefined, undefined, start),
        service.applyTrustedResult(
          { ...event, eventId: randomUUID() },
          undefined,
          undefined,
          start,
        ),
      ]);
      expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
      await service.applyTrustedResult(
        { ...event, eventId: randomUUID(), type: 'refund', amountMinor: 3000 },
        undefined,
        undefined,
        start,
      );
      await expect(
        service.applyTrustedResult(
          {
            ...event,
            eventId: randomUUID(),
            type: 'credit',
            amountMinor: 3000,
          },
          undefined,
          undefined,
          start,
        ),
      ).rejects.toThrow('exceed');
      expect((await state(v.id)).features).toEqual(['WEBSITE']);
      const stale: any = await service.quote(
        owner,
        v.id,
        { planId: full.id },
        middle,
      );
      await expect(
        service.applyTrustedResult(
          {
            ...event,
            eventId: randomUUID(),
            operationId: stale.id,
            amountMinor: stale.amountMinor,
          },
          undefined,
          undefined,
          new Date(middle.getTime() + 16 * 60000),
        ),
      ).rejects.toThrow('Stale');
    });
    it('period changes begin at the existing renewal and retired agreements retain their price', async () => {
      const annual = await db.plan.create({
        data: {
          key: randomUUID(),
          name: 'Annual Website',
          priceMinor: 50000,
          billingPeriod: 'YEAR',
          features: { create: { feature: { connect: { key: 'WEBSITE' } } } },
        },
      });
      const v = await venue();
      await action(
        v.id,
        'GRANT_ACTIVE',
        { planId: website.id, confirm: true },
        start,
      );
      await action(v.id, 'SCHEDULE_CHANGE', { planId: annual.id });
      await new CommercialLifecycleService(db).reconcile(v.id, renewal);
      await db.plan.update({
        where: { id: annual.id },
        data: { status: 'RETIRED', priceMinor: 60000 },
      });
      const q = await pay(v.id, annual, renewal);
      expect(q.amountMinor).toBe(50000);
      expect(
        (await state(v.id, renewal)).venue.subscription?.currentPeriodEndsAt,
      ).toEqual(at('2028-10-25'));
    });
    it('scheduled downgrade rejects stale confirmed prices; upgrades ignore lower catalog price when capabilities grow', async () => {
      const v = await venue();
      await pay(v.id, full);
      await expect(
        action(v.id, 'SCHEDULE_CHANGE', {
          planId: website.id,
          expectedPriceMinor: 1,
          expectedCurrency: 'GEL',
          expectedBillingPeriod: 'MONTH',
        }),
      ).rejects.toThrow('terms changed');
      const cheap = await db.plan.create({
        data: {
          key: randomUUID(),
          name: 'Promotional Full',
          priceMinor: 1000,
          features: {
            create: ['WEBSITE', 'POS'].map((key) => ({
              feature: { connect: { key } },
            })),
          },
        },
      });
      const w = await venue();
      await pay(w.id, website);
      const q: any = await service.quote(
        owner,
        w.id,
        { planId: cheap.id },
        middle,
      );
      expect(q.kind).toBe('UPGRADE');
      expect(q.amountMinor).toBe(0);
      expect((await state(w.id)).features).toEqual(['WEBSITE']);
    });
  },
);
