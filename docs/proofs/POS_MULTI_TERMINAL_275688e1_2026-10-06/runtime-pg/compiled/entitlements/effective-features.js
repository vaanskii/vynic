"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveEffectiveFeatures = resolveEffectiveFeatures;
const client_1 = require("@prisma/client");
/**
 * The one place plan features and Venue overrides are combined.
 *
 * Precedence: an override always wins over the plan default. The absence of an
 * override row is a third state — defer to the plan — so ENABLED grants a
 * feature the plan lacks and DISABLED withholds one the plan includes.
 *
 * Pure on purpose: the ordering rule is the part worth testing exhaustively,
 * and it should not need a database to do it.
 */
function resolveEffectiveFeatures(planFeatureKeys, overrides) {
    const effective = new Set(planFeatureKeys.filter((key) => key !== 'NON_FISCAL_CLOSE'));
    for (const override of overrides) {
        if (override.effect === client_1.FeatureOverrideEffect.ENABLED) {
            effective.add(override.key);
        }
        else {
            effective.delete(override.key);
        }
    }
    return [...effective].sort();
}
