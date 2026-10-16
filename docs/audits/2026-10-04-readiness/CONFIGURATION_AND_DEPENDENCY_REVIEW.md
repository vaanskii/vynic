# Configuration and dependency review

**Date:** 2026-10-04 UTC. Follow-up to [READINESS_AUDIT.md](READINESS_AUDIT.md), after explicit permission to send dependency names and versions to npm. **The production NO-GO decision remains.** No fixes, installations, upgrades, environment edits, deployment or Windows POS interaction were performed.

## 1. Authorized npm result

The approved command ran once in `apps/backend`:

```sh
npm audit --omit=dev --ignore-scripts --json --cache=/tmp/vynic-readiness-npm-cache --fetch-retries=0 --fetch-timeout=15000
```

It completed with exit 1 because it found **13 affected dependency entries: 11 high, 2 moderate, zero critical**. This counts transitive/meta findings, not 13 independent exploits. Reachability and exploitability were not established. This covers the backend production dependency graph, not frontend, Dart, Go or container OS dependencies.

| npm severity | Locked packages and versions |
|---|---|
| High | `@fastify/busboy` 3.2.0; `@grpc/grpc-js` 1.14.4; `@nestjs/platform-express` 11.1.27; `@prisma/config` 6.19.3; `axios` 1.18.0; `deepmerge-ts` 7.1.5; `engine.io` 6.6.9; `fast-xml-parser` 5.9.3; `multer` 2.1.1; `prisma` 6.19.3; `socket.io-parser` 4.2.6 |
| Moderate | `protobufjs` 7.6.4; `qs` 6.15.2 |

Evidence: [raw npm JSON](evidence/npm-audit-approved.json), [summary, dependency versions and advisory links](evidence/npm-audit-summary.json), [stderr](evidence/npm-audit-approved.stderr). Backend lockfile SHA-256: `a473f6f0332845314368960f34e5d55f125d5898e3ca7672ad82cdd98369ff1f`.

Before network access, local npm 11.13.0 implementation and effective configuration were inspected. Its bulk request body contains dependency names mapped to semantic-version arrays: 342 package names, 362 name/version entries, excluding the root application. No configured registry credentials, custom headers, proxy or sensitive npm runtime options were found. The inspected path uses `https://registry.npmjs.org/-/npm/v1/security/advisories/bulk`; it has no legacy audit fallback. No `.env`, credentials, source or business data was included in the audit body. Normal HTTP/npm client metadata accompanies the request. [Payload preflight](evidence/npm-payload-preflight.json), [configuration preflight](evidence/npm-preflight-config.json).

**Priority / acceptance — OPS-03, P1 release gate:** reproduce findings on the frozen release candidate, trace direct/transitive dependency paths and exposed code paths, then apply reviewed dependency changes in an isolated implementation task. Prioritize internet-facing parsing/upload/socket and outbound HTTP paths where applicable. Verify the resulting lockfile, runtime image, boundary tests and scanner output; document any remaining exception with rationale, owner and expiry. Do not infer that a reported package is exploitable merely because it is installed, or safe because it is transitive. npm's suggested Prisma/config resolution is **6.12.0**, lower than the installed 6.19.3 and marked outside the allowed semver range; it is not an approved upgrade plan. No `npm audit fix` or forced resolution was run.

The initial automatic-review denial is resolved for this bounded scan by the user's subsequent explicit approval. It does not authorize further external scans or dependency changes.

## 2. What changes for deployment

**Yes: production needs a separate, validated configuration.** The inspected files are local development/local Docker inputs. Renaming an env file or replacing addresses alone is insufficient: runtime backend configuration, public web build configuration, native build configuration and installed update trust have different lifecycles.

| Surface | When selected | Deployment requirement / verified code |
|---|---|---|
| Backend | Process startup / container runtime | Supply production DB credentials, signing/encryption keys, HTTPS origins and persistent media path. `apps/backend/src/main.ts:1–13` loads dotenv and validates before Nest. `compose.yaml:9–28` explicitly injects selected keys; merely adding an arbitrary variable to the Compose env file does not pass it to the backend. |
| Backend production guards | Exact `NODE_ENV=production` | `apps/backend/src/shared/deployment-config.ts:22` returns early otherwise. Hosted staging should use production guards with staging data/origins; `NODE_ENV=staging` does not enable them. Compose and the runtime Dockerfile already set production. The local Docker exception is explicit and restricted to its isolated DB/domain (`deployment-config.ts:58–68`). |
| Browser applications | Build time | `deploy/frontend.Dockerfile:8–11` compiles same-origin `VITE_API_BASE_URL=""`, `VITE_API_URL="/api"` and public `VITE_COMING_SOON`. Changing the later nginx container environment does not rewrite built JavaScript. Never put a secret in `VITE_*`. |
| POS / Manager API | Native build time | `apps/operations/tool/product.py:40–59` supplies `VYNIC_ENV` and HTTPS `VYNIC_API_URL` through Dart defines. `lib/core/services/sync/api_config.dart:11–38` validates them; editable fallback requires a development debug build. Production API changes require a qualified native build/update, not a backend `.env` edit. |
| Setup / Edge updater | Signed distribution metadata plus installed receipt/configuration | `apps/edge/internal/setup/setup.go:235–251` preserves the installed distribution/repair baseline and rejects changed repair metadata. A new backend env or rerun installer does not migrate an old saved feed. Use a reviewed endpoint migration plus stable HTTPS hosting, metadata renewal and retained trust/anti-rollback controls. |

The backend startup guard requires the DB URL, JWT/refresh/cookie keys and media directory; checks configured key lengths, master-key format, exact proxy IPs and HTTPS origins; and rejects wildcard CORS. Compose additionally requires the Platform JWT and payment master key. These are useful validation checks, **not verification that secrets are random, providers work or infrastructure is ready**. Production `.env.production` is not automatically selected by the inspected application bootstrap: select the file through the deployment mechanism or inject equivalent secrets. `scripts/docker.sh:8` explicitly selects `.env.docker` and `compose.local.yaml` for local work. The backend image does not copy application `.env` files (`apps/backend/Dockerfile:5–22`).

Keep the public payment callback origin (`API_URL`) and native API origin (`DEVICE_API_BASE_URL`) distinct according to their proxy routing. The production example uses the public site and API subdomain respectively; do not copy a LAN IP. Also, `apps/platform-web/src/site-origins.ts:2–20` currently recognizes/hardcodes `admin.vynic.ge` and `vynic.ge`. Choosing different production domains needs an owner-reviewed change to that routing, not just new env values. Claude's web files were inspected read-only.

## 3. Local environment observations, values withheld

[Redacted inventory](evidence/environment-inventory-redacted.json) records variable names, presence/classification and file hashes, never secret values. This is a file snapshot, not inspection of running processes, containers or provider accounts.

- Root `.env` and `.env.production` are absent. `.env.docker` exists with local HTTP/domain settings and the required secret categories set. Checked JWT/cookie/Platform values pass the minimum-length rule; no entropy/security guarantee is implied.
- `apps/backend/.env` contains local DB/origin settings, JWT/cookie/Platform keys, legacy provider/bootstrap/shared-key categories and an external credential-file path. The credential file was not opened. `NODE_ENV`, `PAYMENT_INTEGRATION_MASTER_KEY`, `WEBSITE_MEDIA_DIR` and `DEVICE_API_BASE_URL` are absent **from this file**; they could still be injected by a process. This file should not serve as a production deployment manifest.
- Backend `FRONTEND_URL` is assigned twice with identical values: no current disagreement, but remove duplication in a future owned config cleanup. `CUSTOM_WEBSITE_DEV_PORT` is obsolete; current local custom-site mapping uses `CUSTOM_WEBSITE_LOCAL_FRONTENDS` (`apps/backend/src/website/custom/custom-website-local.ts:18–21`). Neither belongs in a production routing plan.
- Platform web has a local `VITE_API_BASE_URL`; restaurant web has a `VYNIC_WEBSITE_API` entry. The latter is read from `process.env` by its development proxy (`vite.config.ts:22`); this audit does not claim a `.env` entry automatically populates config-time `process.env`. Custom web's local env file has no active assignments in the inventory.
- Operations `.env`/`.env.windows` retain legacy role/address/shared-key/printer/ingest categories. Current API identity uses Dart defines and enrolled Device credentials; the legacy shared-key getter returns null (`api_config.dart:63–69`). `product.py:13,62–64` excludes `.env*` from prepared source/assets. Do not treat legacy env files as the production POS/Manager configuration or as permission to enable frozen callback paths.

**Key/data compatibility is a release requirement.** Generate independent secrets for a fresh, empty production environment. When moving/restoring existing encrypted records, preserve the matching encryption keys or execute an explicit re-encryption migration. `COOKIE_ENCRYPTION_KEY` also derives the staff PIN vault key (`apps/backend/src/auth/staff-pin-vault.service.ts:21,48`); payment records depend on `PAYMENT_INTEGRATION_MASTER_KEY` (`payment-integrations/payment-config.crypto.ts:5`). Blindly replacing those values can make retained data unreadable. Back up keys under separate controlled custody and prove recovery with synthetic encrypted records.

Legacy global `BOG_CLIENT_*` entries are read by the integration import script; the current payment path uses encrypted per-Venue integrations. `SUPER_ADMIN_*` bootstraps a **WebsiteUser**, not a PlatformUser (`shared/bootstrap/bootstrap.service.ts:67–111`). Copying the old file does not establish the intended production operator or correct payment integration.

**Configuration acceptance before deployment:** choose domains/provider; create a separate secret-backed manifest; pass production guards without the local exception; verify actual proxy/callback/native routes; build web/native artifacts against those routes; rehearse DB/media/key restore; and qualify installed feed migration/renewal. Changing configuration does not repair MGR-02/05 or WEB-01/03/04, qualify printers, establish Authenticode or prove safe data rollback. Those gates in the main audit remain open.
