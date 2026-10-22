import { commercialState } from '../entitlements/commercial-state';
import { CustomerService } from './customer.service';
import { SubscriptionService } from '../subscriptions/subscription.service';
import { CustomerActor, CustomerGuard } from './customer-auth';
import type { CustomerPrincipal } from './customer-auth';
import { PlatformCommercialService } from '../platform/platform-commercial.service';
import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  Get,
  HttpException,
  Injectable,
  Param,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { EnrollmentRateLimiter } from '../edge/enrollment-rate-limiter';
import { requireText } from '../platform/platform-validation';
import { PlatformAuthGuard } from '../platform/platform-auth.guard';
import { PlatformActor } from '../platform/platform-auth-context';
import type { PlatformPrincipal } from '../platform/platform-auth-context';
import { OwnerInvitationsService } from './owner-invitations.service';

@Injectable()
export class OnboardingRequestsService {
  constructor(
    private readonly db: PrismaService,
    private readonly limiter: EnrollmentRateLimiter,
    private readonly invitations: OwnerInvitationsService,
    private readonly owners: CustomerService,
    private readonly commercial: PlatformCommercialService,
  ) {}
  async submit(body: Record<string, unknown>, ip: string) {
    const email = requireText(body.email, 'Email', { max: 254 }).toLowerCase();
    if (
      !this.limiter.consume('access-request-ip:' + ip, 5, 3600000) ||
      !this.limiter.consume('access-request-email:' + email, 3, 86400000)
    )
      throw new HttpException('Too many requests. Try again later.', 429);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      throw new BadRequestException('Invalid email');
    const data = {
      applicantName: requireText(body.applicantName, 'Name', { max: 100 }),
      businessName: requireText(body.businessName, 'Business name', {
        max: 100,
      }),
      email,
      phone: requireText(body.phone, 'Phone', { max: 40 }),
      note: body.note ? requireText(body.note, 'Note', { max: 1000 }) : null,
      requestedPlanId: body.requestedPlanId
        ? requireText(body.requestedPlanId, 'Plan')
        : null,
    };
    if (
      data.requestedPlanId &&
      !(await this.db.plan.findFirst({
        where: { id: data.requestedPlanId, status: 'ACTIVE' },
      }))
    )
      throw new BadRequestException('Plan unavailable');
    await this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtextextended(${email}, 219))::text`;
      if (
        await tx.onboardingRequest.findFirst({
          where: { email, requestedVenueId: null, status: 'PENDING' },
        })
      )
        throw new ConflictException('A request is already awaiting review');
      await tx.onboardingRequest.create({ data });
    });
    return { received: true }; // No account, tenant, domain, subscription or session created.
  }
  async requestTrial(
    actor: CustomerPrincipal,
    venueId: string,
    body: Record<string, unknown>,
  ) {
    const venue = await this.owners.venue(actor, venueId);
    const account = await this.db.customerAccount.findUniqueOrThrow({
      where: { id: actor.customerAccountId },
    });
    if (!this.limiter.consume('trial-request:' + venueId, 3, 86400000))
      throw new HttpException('Too many requests. Try again later.', 429);
    const requestedPlanId = body.requestedPlanId
      ? requireText(body.requestedPlanId, 'Plan')
      : null;
    if (
      requestedPlanId &&
      !(await this.db.plan.findFirst({
        where: { id: requestedPlanId, status: 'ACTIVE' },
      }))
    )
      throw new BadRequestException('Plan unavailable');
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${venueId} FOR UPDATE`;
      const state = await commercialState(tx, venueId);
      if (state.allowed)
        throw new ConflictException('This venue already has commercial access');
      if (
        await tx.onboardingRequest.findFirst({
          where: { requestedVenueId: venueId, status: 'PENDING' },
        })
      )
        throw new ConflictException('A request is already awaiting review');
      const row = await tx.onboardingRequest.create({
        data: {
          applicantName: account.displayName,
          businessName: venue.name,
          email: account.email,
          phone: venue.phone ?? '',
          requestedVenueId: venueId,
          requestedByAccountId: account.id,
          requestedPlanId,
          note: body.note
            ? requireText(body.note, 'Note', { max: 1000 })
            : null,
        },
      });
      await tx.customerAuditEvent.create({
        data: {
          customerAccountId: account.id,
          action: 'trial.requested',
          targetType: 'Venue',
          targetId: venueId,
          metadata: { requestId: row.id, requestedPlanId },
        },
      });
      return { received: true };
    });
  }
  async pendingTrial(actor: CustomerPrincipal, venueId: string) {
    await this.owners.venue(actor, venueId);
    return this.db.onboardingRequest.findFirst({
      where: { requestedVenueId: venueId, status: 'PENDING' },
      select: { id: true, status: true },
    });
  }
  list() {
    return this.db.onboardingRequest.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
  }
  plans() {
    return this.db.plan.findMany({
      where: { status: 'ACTIVE' },
      select: {
        id: true,
        name: true,
        description: true,
        priceMinor: true,
        currency: true,
        billingPeriod: true,
        features: {
          select: { feature: { select: { key: true, name: true } } },
        },
      },
      orderBy: { priceMinor: 'asc' },
    });
  }
  async review(
    actor: PlatformPrincipal,
    id: string,
    body: Record<string, unknown>,
  ) {
    if (!['APPROVED', 'REJECTED'].includes(String(body.status)))
      throw new BadRequestException('Approve or reject the request');
    return this.db.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT "id" FROM "pos"."OnboardingRequest" WHERE "id"=${id} FOR UPDATE`;
      const request = await tx.onboardingRequest.findUniqueOrThrow({
        where: { id },
      });
      if (request.status !== 'PENDING')
        throw new ConflictException('Request already reviewed');
      const outcome =
        body.outcome ?? (request.requestedVenueId ? 'TRIAL' : 'NO_PLAN');
      if (
        body.status === 'APPROVED' &&
        !['TRIAL', 'NO_PLAN'].includes(String(outcome))
      )
        throw new BadRequestException(
          'Choose approval without package or with Trial',
        );
      if (
        body.status === 'APPROVED' &&
        outcome === 'TRIAL' &&
        (!body.planId || !body.trialEndsAt)
      )
        throw new BadRequestException('Choose a trial plan and end date');
      const prepared =
        body.status === 'APPROVED' && !request.requestedVenueId
          ? await this.invitations.provision(
              actor,
              {
                organizationName: request.businessName,
                name: request.businessName,
                phone: request.phone,
                email: request.email,
                // Provision the shell and invitation in the same transaction as explicit trial approval.
                subscriptionStatus: 'NO_PLAN',
              },
              tx,
            )
          : null;
      const targetVenueId = prepared?.venue.id ?? request.requestedVenueId;
      if (body.status === 'APPROVED' && targetVenueId && outcome === 'TRIAL') {
        await tx.$queryRaw`SELECT "id" FROM "pos"."Venue" WHERE "id"=${targetVenueId} FOR UPDATE`;
        const state = await commercialState(tx, targetVenueId);
        if (state.allowed)
          throw new ConflictException('Venue already has commercial access');
        // Same lifecycle action as a manual Platform Trial, so approval and
        // manual assignment cannot provision differently.
        await new SubscriptionService(this.db).action(
          actor,
          targetVenueId,
          {
            action: 'TRIAL',
            planId: body.planId,
            trialEndsAt: body.trialEndsAt,
            websiteMode: body.websiteMode,
            reason: body.note || 'Access request approved',
          },
          tx,
        );
      }
      const reviewNote = body.note
        ? requireText(body.note, 'Review note', { max: 1000 })
        : null;
      const result = await tx.onboardingRequest.update({
        where: { id },
        data: {
          status: String(body.status),
          reviewedBy: actor.platformUserId,
          reviewedAt: new Date(),
          reviewNote,
          approvedVenueId: prepared?.venue.id ?? request.requestedVenueId,
        },
      });
      await tx.platformAuditEvent.create({
        data: {
          platformUserId: actor.platformUserId,
          action: 'onboarding.request_reviewed',
          targetType: 'OnboardingRequest',
          targetId: id,
          metadata: {
            status: result.status,
            venueId: targetVenueId,
            outcome: String(outcome),
            planId: outcome === 'TRIAL' ? String(body.planId) : null,
            note: reviewNote,
          },
        },
      });
      return { request: result, prepared };
    });
  }
}
@Controller('customer/access-requests')
export class PublicAccessRequestsController {
  constructor(private readonly service: OnboardingRequestsService) {}
  @Post() submit(
    @Body() body: Record<string, unknown>,
    @Req() req: { ip: string },
  ) {
    return this.service.submit(body, req.ip);
  }
  @Get('plans') plans() {
    return this.service.plans();
  }
}
@Controller('platform/onboarding/requests')
@UseGuards(PlatformAuthGuard)
export class PlatformAccessRequestsController {
  constructor(private readonly service: OnboardingRequestsService) {}
  @Get() list() {
    return this.service.list();
  }
  @Post(':id/review') review(
    @PlatformActor() actor: PlatformPrincipal,
    @Param('id') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.review(actor, id, body);
  }
}

@Controller('customer/venues/:venueId/trial-requests')
@UseGuards(CustomerGuard)
export class CustomerTrialRequestsController {
  constructor(private readonly service: OnboardingRequestsService) {}
  @Get() pending(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
  ) {
    return this.service.pendingTrial(actor, id);
  }
  @Post() submit(
    @CustomerActor() actor: CustomerPrincipal,
    @Param('venueId') id: string,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.requestTrial(actor, id, body);
  }
}
