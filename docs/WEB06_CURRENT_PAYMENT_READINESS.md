# WEB-06 — Current payment integration readiness

Status: **DONE for the read-only status/readiness bug**. No deployment, live
credentials, payment policy or bank operation is included.

After BOG rotation, `PaymentIntegrationsService.status` already selected the
highest revision, while `WebsiteCapabilitiesService` read an unordered row.
Real isolated HTTP/PostgreSQL reproduction returned merchant revision 2 as
configured and Website payments/reservations as unavailable in both SAAS and
CUSTOM. The new regression failed on that original source.

`latestBogIntegrationStatus` now supplies merchant status, Website capabilities
and the CUSTOM operator view with the same Venue/BOG
query ordered by revision descending. It selects only enabled/revision/createdAt;
no ciphertext or client secret is loaded or decrypted. Missing configuration
and the latest disabled revision remain distinct unavailable states. Existing
entitlement and capability switches still control access.

Payment creation, credentials-by-ID, encrypted configuration, rotation/disconnect,
provider callback/settlement and history code are unchanged. No migration or
backfill is required. WEB-01/03/04 and production provider/hardware/release gates
remain separate and open.

Seven new real HTTP/PostgreSQL cases cover both renderers, rotation, disconnect/
reconnect, revision-versus-timestamp ordering, another Venue's missing config,
owner denial, keyless/non-secret status reads, immutable stored rows, historical
pinned credentials, entitlement removal and explicit policy switches. The
existing W1 suite checks provider calls with mocked bank transport, including
old-revision settlement after rotation/disconnect. No real provider call ran.

Final source/check results and opt-in test accounting are retained in
`docs/proofs/WEB06_3463ee40_2026-10-13/qualification.json`.

The 2026-10-14 CUSTOM follow-up closes the remaining unordered read in
`CustomWebsiteService.facts`. The new HTTP/PostgreSQL regression reproduced
`DISABLED` after rotation while the current revision was enabled. Three added
cases cover the operator view after rotation, a latest disabled revision with
an older enabled row and skewed timestamps, reconnect, missing configuration,
entitlement removal, Venue isolation, owner/anonymous denial, keyless metadata
reads and unchanged pinned history. The production change only imports and
calls the existing selector; no schema or permission change is needed.

Final validation: 10 focused cases; 874 backend aggregate passes / 843 skips;
17 existing CUSTOM cases and 8 W1 cases, with mocked bank transport. These are
899 distinct passing case records; the focused 10 also ran in the aggregate.
818 opt-in cases were not executed across these runs. Backend types/build,
changed-boundary lint (zero errors/warnings), formatting and `git diff --check`
pass. All databases were disposable on an owned loopback PostgreSQL cluster;
75 current migrations applied to fresh databases. No live services or bank
were used. Exact evidence, qualification limits and owned-resource cleanup:
`docs/proofs/WEB06_CUSTOM_STATUS_3463ee40_2026-10-14/qualification.json`.
