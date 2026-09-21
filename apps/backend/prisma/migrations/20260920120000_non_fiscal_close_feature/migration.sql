-- Preserve existing POS plan behavior; operators can now override this capability.
INSERT INTO "pos"."Feature" ("id","key","name","updatedAt")
VALUES ('feature-non-fiscal-close','NON_FISCAL_CLOSE','არაფისკალური დახურვა',CURRENT_TIMESTAMP)
ON CONFLICT ("key") DO NOTHING;
INSERT INTO "pos"."PlanFeature" ("planId","featureId")
SELECT pf."planId", f."id" FROM "pos"."PlanFeature" pf
JOIN "pos"."Feature" base ON base."id"=pf."featureId" AND base."key"='POS'
CROSS JOIN "pos"."Feature" f WHERE f."key"='NON_FISCAL_CLOSE'
ON CONFLICT DO NOTHING;
