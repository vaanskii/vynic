"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.commercialState = commercialState;
exports.requireCommercialFeature = requireCommercialFeature;
const common_1 = require("@nestjs/common");
const effective_features_1 = require("./effective-features");
const subscription_policy_1 = require("./subscription-policy");
/** Shared by reads and mutations under the Venue lock. */
async function commercialState(tx, venueId, now = new Date()) {
    const venue = await tx.venue.findUnique({
        where: { id: venueId },
        include: {
            subscription: true,
            planAssignment: {
                include: {
                    plan: { include: { features: { include: { feature: true } } } },
                },
            },
            featureOverrides: { include: { feature: true } },
            websiteConfig: true,
        },
    });
    if (!venue)
        throw new common_1.NotFoundException('Venue not found');
    const planFeatures = (0, effective_features_1.resolveEffectiveFeatures)(venue.planAssignment?.plan.features.map((f) => f.feature.key) ?? [], venue.featureOverrides.map((f) => ({
        key: f.feature.key,
        effect: f.effect,
    })));
    const legacy = venue.legacyCommercialAccess && !venue.subscription;
    const allowed = (legacy || !!venue.planAssignment) &&
        (!venue.subscription?.billingManaged ||
            !['ACTIVE', 'PAST_DUE'].includes(venue.subscription.status) ||
            (!!venue.subscription.currentPeriodEndsAt &&
                venue.subscription.currentPeriodEndsAt > now)) &&
        (0, subscription_policy_1.commercialAccessAllowed)(venue.subscription?.status, venue.subscription?.trialEndsAt, legacy, now);
    return {
        venue,
        planFeatures,
        allowed,
        features: allowed ? planFeatures : [],
    };
}
async function requireCommercialFeature(tx, venueId, feature) {
    const state = await commercialState(tx, venueId);
    if (!state.features.includes(feature))
        throw new common_1.ForbiddenException(`${feature} access is disabled`);
    return state;
}
