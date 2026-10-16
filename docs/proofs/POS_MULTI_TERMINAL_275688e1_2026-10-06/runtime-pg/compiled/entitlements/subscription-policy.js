"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.commercialAccessAllowed = commercialAccessAllowed;
/** Missing subscriptions are allowed only for migration-marked legacy Venues. */
function commercialAccessAllowed(status, trialEndsAt, legacyCommercialAccess = false, now = new Date()) {
    if (status == null)
        return legacyCommercialAccess;
    if (status === 'TRIAL')
        return !!trialEndsAt && trialEndsAt > now;
    return status === 'ACTIVE' || status === 'PAST_DUE';
}
