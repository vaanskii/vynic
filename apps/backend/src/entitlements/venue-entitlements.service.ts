import { profileSelect } from '../venue-profile/venue-profile';
import { Injectable } from '@nestjs/common';
import { WebsiteMode } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import { commercialState } from './commercial-state';
import { CommercialLifecycleService } from './commercial-lifecycle.service';
export interface VenueWebsiteAccess {
  entitled: boolean;
  configuredMode: WebsiteMode;
  effectiveMode: WebsiteMode;
  consistent: boolean;
}
/** Commercial access never gates Device authentication, sync, or local POS completion. */
@Injectable()
export class VenueEntitlementsService {
  constructor(private readonly prisma: PrismaService) {}
  private async state(venueId: string) {
    // The shared date check also fails closed if a timer is late.
    const row = await this.prisma.venueSubscription.findUnique({
      where: { venueId },
    });
    if (
      (row?.status === 'TRIAL' &&
        (!row.trialEndsAt || row.trialEndsAt <= new Date())) ||
      (row?.billingManaged &&
        row.currentPeriodEndsAt &&
        row.currentPeriodEndsAt <= new Date())
    )
      await new CommercialLifecycleService(this.prisma).reconcile(venueId);
    return commercialState(this.prisma, venueId);
  }
  async effectiveFeatures(venueId: string): Promise<string[]> {
    return (await this.state(venueId)).features;
  }
  async planFeatures(venueId: string): Promise<string[]> {
    return (await this.state(venueId)).planFeatures;
  }
  async hasFeature(venueId: string, featureKey: string): Promise<boolean> {
    return (await this.effectiveFeatures(venueId)).includes(featureKey);
  }
  async commercialAccess(venueId: string): Promise<boolean> {
    return (await this.state(venueId)).allowed;
  }
  async snapshot(venueId: string) {
    const state = await this.state(venueId);
    const profile = await this.prisma.venue.findUniqueOrThrow({
      where: { id: venueId },
      select: profileSelect,
    });
    return {
      profile,
      features: state.features,
      subscription: state.venue.subscription,
      commercialAccess: state.allowed,
    };
  }
  async websiteAccess(venueId: string): Promise<VenueWebsiteAccess> {
    const state = await this.state(venueId);
    const entitled = state.features.includes('WEBSITE');
    const configuredMode = state.venue.websiteConfig?.mode ?? WebsiteMode.NONE;
    return {
      entitled,
      configuredMode,
      effectiveMode: entitled ? configuredMode : WebsiteMode.NONE,
      consistent: entitled === (configuredMode !== WebsiteMode.NONE),
    };
  }
}
