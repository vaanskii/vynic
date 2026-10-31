# Rotation readiness — source preparation, not an executed rotation

No production credential, database row, DNS record or deployment was changed by
this preparation. Only synthetic keys, in-memory rows and loopback HTTP are used
by the rotation tests. The protected Worker workflow lives in `.github/workflows`;
its credential and actual deployment are separately verified. This document is
not an installer qualification receipt.

## Confirmed metadata and unresolved identity checks

Render workspace `tea-cspa7ujgbbvc73bad3lg` contains available PostgreSQL
`vynic-db`, ID `dpg-dbdjpc9srm7s73c0b81g-a`, database `vynic_db`, displayed user
`vynic_db_user`, Frankfurt. This is provider metadata only. The exact association
to `vynic-api`'s current DATABASE_URL and all external consumers must still be
confirmed without exposing the URL. No business database query was made.

The existing GitHub read credential's documented identity is
`Vynic Render releases read`, restricted to `vaanskii/vynic-releases`, Contents
and Metadata read, expiring November 23, 2026. The backend source consumes only
that repository's draft release asset. Actual token ID/current provider metadata
must be confirmed before revocation; a friendly name alone is not sufficient.

## Bounded proxy transition

Source supports the primary `VYNIC_WEB_PROXY_SECRET` and, only when all fields
are present, `VYNIC_WEB_PROXY_PREVIOUS_SECRET`, `VYNIC_WEB_PROXY_ROTATION_START`
and `VYNIC_WEB_PROXY_ROTATION_END`. Times are exact UTC ISO strings including
milliseconds. Keys must be distinct and strong; duration is positive and at
most 30 minutes. Incomplete/invalid settings stop startup before DB connection.
Old-key admission ends at the fixed timestamp or monotonic deadline, whichever
comes first, and cannot reopen in that process. Restart does not reset the
absolute window. The primary remains valid after the overlap expires. A trusted
server clock remains a prerequisite; this is not a defense against an operator
altering host time and restarting the server before the configured cutoff.

Cutover, only after approval and secure value handling:

1. Publish/review this exact source and deploy with no transition configured;
   existing behavior remains one key. Verify all three existing frontend paths.
2. Prepare one independent replacement shared secret, kept only in secure secret
   settings. Stage Render with new primary, old previous and one fixed short
   interval. Start the window at the actual cutover, not during build preparation.
3. Deploy Render, then the Production environments of `vynic-platform-web`,
   `vynic-restaurant-web`, `vynic-vankisi-custom-web` with the new primary. Preserve
   auth/session/tenant settings and mail-disabled state. Probe each application's
   health and authenticated transport without emitting credential headers.
4. Confirm all traffic uses the new key, remove the three transition fields and
   deploy Render. Verify the old key is rejected and the new key succeeds.

If a frontend misses the deadline it fails closed; do not silently extend the
window or restore a compromised primary. Recovery is to finish switching that
consumer or use an explicitly approved maintenance window. The overlap preserves
the old key's risk for a maximum of 30 minutes; it is not immediate revocation.
This change does not affect the independent R2 download gateway secret.

## Cookie/PIN migration rehearsal and production gate

`test/pin-key-rotation-rehearsal.ts` is a pure, non-runtime design proof. It reads
no env/files/DB, returns only ciphertext replacements and exposes no CLI. Tests
create actual StaffPinVault v1 ciphertext with synthetic keys, validate every
row's authenticated decryption and mapping shape, encrypt with a distinct key,
verify readback, and exercise recovery from original ciphertext. Duplicate Venue
rows, legacy/plaintext/malformed ciphertext and wrong keys stop the whole plan.
Tests model a stale-row abort, not real PostgreSQL transaction isolation.

Do not use StaffPinVault.read for migration: its current decrypt-failure fallback
returns an empty map, which must never be interpreted as successful migration.
Production migration must first deploy fail-closed error handling and prove the
following against a populated disposable PostgreSQL instance:

- inventory every encryption consumer and classify legacy records explicitly;
- authorize and verify a restricted encrypted backup and key recovery plan;
- stop/serialize all PIN-map writers, including POS staff sync and Manager/Admin
  changes, before snapshot and re-encryption; ordinary startup must not overwrite
  unavailable maps;
- lock and compare every row's original ciphertext in one controlled transaction
  or an equivalently reviewed resumable protocol; zero partial commits;
- verify row counts, ownership and semantic equality without printing PINs;
- switch the runtime key and reconnect consumers, force website-cookie login;
- prove rollback before writes resume. After writes resume, never restore an old
  snapshot over newer business changes; recovery needs an explicit forward plan.

No keyring or migration was added to the production PIN service. Old encrypted
backups need controlled retention/recovery access; this plan does not authorize
their deletion or storage of keys beside them. Strings in JS cannot be guaranteed
zeroized; buffer clearing in the rehearsal is not a complete secret-custody claim.

## Uncertain JWT/license exposure: design only

No raw secret response was reread. JWT/license exposure remains unconfirmed.
Conservative JWT replacement requires coordinated access/refresh/admin signer
changes and fresh logins. Do not retain potentially compromised JWT keys merely
to avoid login prompts. Device credential verification is a separate database
verifier, not JWT signing. No customer/device identities are to be reset.

The current POS accepts one compiled `VYNIC_LICENSE_PUBLIC_KEY`. A future planned
rollover can add a bounded compiled public-key set with explicit key IDs, fixed
Ed25519 algorithm and independent activation/retirement policy, delivered by the
separate trusted package updater. The backend can then switch issuance only after
compatible clients are installed. An old key's signature cannot authorize its own
indefinite extension or addition of a new key. Tests must cover unknown key IDs,
algorithm substitution, retirement, clock uncertainty, restored anchors and old
client behavior. Existing single-pin beta19 does not gain this ability remotely.

For suspected signing-key compromise, continued old-key trust is not a safe
compatibility solution. Reissue/requalify the installer with the replacement pin,
withdraw the old candidate from distribution and require affected clients to
update. Old offline clients cannot be instantly revoked by a server-only change.
This is a hard gate before calling the installer ready for real users. No such
license key or code change was made here.

## Least-privilege CI reconciliation

The selected Worker deployment service is GitHub Actions with a narrowly scoped
account-owned token. Cloudflare Builds remains disabled. The executable
workflow is `.github/workflows/installer-worker.yml`; its default dispatch mode
runs checks only and has no secrets. Deployment additionally requires main, an
exact approved SHA, passing checks, an explicit deploy input, and approval in
`installer-worker-production`. Actions and Node are pinned. See
`docs/PRIVATE_R2_RELEASES.md` for verified environment protections and handoff.

The deploy stages use `wrangler versions upload` followed by deployment of the
exact validated upload receipt UUID. Unlike `wrangler deploy`, these commands do
not apply route/custom-domain/cron trigger changes; Wrangler explicitly directs
those to `triggers deploy`, which is absent here. Existing wrangler.json remains
the declarative routing reference, while route creation/change is a separate
approved operation. No DNS/zone-edit permission is requested for ordinary CI.

Proposed credential is the dashboard's account token limited to the existing
`vynic-installer-downloads` Worker, stored only as the protected environment secret
`CLOUDFLARE_INSTALLER_WORKER_DEPLOY_TOKEN`. No GitHub App is required. Verify the
actual token permissions and whether existing R2 binding reuse works before
activation; dry-run compilation does not prove remote permissions.
If the provider requires additional privileges, report the exact failed scope;
do not silently substitute account-wide Scripts/KV/R2 or all-zone access.

Build/install scripts run before token injection. The token is available only
to version upload/deploy steps, never to PRs or fork builds. CI deployment access
can replace code that has the R2 binding and runtime secret; protect the source
branch/workflow and reviewers accordingly. Runtime secret and publisher object
credentials are never copied into CI. Windows artifact CI remains separate.

References: [Render credential rotation](https://render.com/docs/postgresql-credentials),
[Cloudflare version deployment](https://developers.cloudflare.com/workers/versions-and-deployments/),
[Workers Builds token defaults](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/).
