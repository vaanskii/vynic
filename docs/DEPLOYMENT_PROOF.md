# Local deployment acceptance — 2026-09-26

Scope: Docker Desktop on this macOS machine; new project `vynic-local-prod`,
PostgreSQL database `vynic_local_prod`. No live database connection, import, dump
or migration was performed. The local override forces PostgreSQL's Docker service
name and the isolated database regardless of any external DATABASE_URL value.

## Image and startup proof

- Backend and all three frontend multi-stage production image builds completed.
- `prisma migrate deploy` applied the existing history to a fresh volume, through
  `20261010120000_shared_website_foundation`, with exit 0. No migrations were created
  or rewritten. A repeat returned `No pending migrations to apply`.
- Six persistent services reported healthy: PostgreSQL, backend, three static
  frontend servers and Traefik. Migration job exited 0.
- Only `127.0.0.1:80->8080` is published; 3000, 5432 and frontend 8080 ports are
  internal. Production Compose configuration also passed `config --quiet` with
  synthetic validation settings; no production services were started.
- Tabla and Vankisi samples use valid stable UUIDs and separate organizations,
  ACTIVE Website-only access, Cloud menu authority and ordinary VenueDomains.
  Repeating the seed preserved existing data and the uploaded media reference.

## HTTP and browser matrix

`python3 scripts/prove-docker-http.py` passed all its checks through the real
Traefik ingress. It connects to loopback with the requested public Host; actual
browser DNS was verified separately without resolver overrides or hosts edits.

| Requirement | Evidence / result |
| --- | --- |
| Vynic public host | 200, built assets 200; browser title `Vynic \| Restaurant POS` |
| Admin host | 200, browser `Vynic Platform Admin` login; separate origin |
| Tabla SAAS | Browser shows Tabla, `Tabla khachapuri` GEL 18, hours 10:00–23:00 |
| Vankisi CUSTOM | Bespoke Vankisi page; `/en/menu` shows `Vankisi mtsvadi` 25 GEL |
| Renderer priority | Different static assets; exact CUSTOM route beats shared wildcard |
| Same-origin APIs | Both hosts return 200 from `/api/website/venue`, `/api/menu`, `/api/website/venue/menu` |
| Tenant isolation | Each API menu includes its own sample dish and excludes the other's |
| Host spoofing | Setting X-Forwarded-Host to the other Venue did not change returned Venue |
| CORS | Foreign Origin refused; no Access-Control-Allow-Origin returned |
| Unknown Venue | API 404; browser displays website unavailable, no fallback restaurant |
| Unrouted hostname | Traefik 404 |
| Admin isolation | Admin `/platform/auth/me` requires auth (401); public-host login POST never reaches it (405); public `/admin` navigates back to public `/en` |
| Website cookies | CSRF + signup + encrypted cookie verification succeed on both hosts; cookies are host-only, HttpOnly, SameSite Strict and local HTTP compatible |
| Browser auth | Test WebsiteUser signed in through Vankisi UI; My Profile/Sign Out persisted after navigation; Sign Out restored Sign In |
| History/asset paths | HTTP nested routes and bundle assets pass on all four hosts; browser CUSTOM `/en/menu` refresh works |
| Shared hours | Both Venue APIs return their own seeded hours through shared Foundation; generic renderer displays them |
| Payment readiness | Unconfigured payment POST fails closed; no real BOG calls or fabricated credentials |
| CUSTOM check | Service used registered `http://vankisi.vynic.localhost/`, frontend 200, API 200/OK, REACHABLE; direct-dev port metadata absent |

Browser qualification used the installed **Brave (Chromium)** on macOS. Google
Chrome is not installed/available to the browser tool, so this is not a claim of
an exact Chrome run. Four nested `.localhost` names worked without `/etc/hosts`.
Brave blocked a direct diagnostic navigation to `/api/auth/verify`; ordinary
website sign-in, persisted authenticated UI and logout worked, and cookie HTTP
round-trips were separately verified by the acceptance script. Browser shields
were not disabled or bypassed.

The bespoke Vankisi footer still displays its existing hard-coded hours/contact
and marketing content. Its shared hours API returns 12:00–23:00 correctly. Rewiring
that renderer is an adjacent frontend task, not a Docker/business-logic change.

## Persistence proof

An image was uploaded through the existing `WebsiteLogoService.upload`, which
checks ACTIVE commercial access, quotas, decodes to WebP and records Venue
ownership. It was referenced by the isolated Tabla sample. The HTTP content hash
was captured before and after backend restart, then after forced backend and all
frontend container recreation:

```text
Database counts at snapshot: Venue=3, WebsiteUser=2, WebsiteMediaAsset=1
Media SHA-256: cbe8992deb0e3098e698e7ff497abe15536b91ec5ccdbf7a968b3574ed569cdb
Backend restart: identical counts, identity and media hash
Backend/frontend recreation: identical counts, identity and media hash
Repeated migrate deploy: identical counts, identity and media hash
```

The third Venue is empty legacy migration scaffolding, not imported restaurant
data. Later browser/HTTP tests add test-only WebsiteUsers, so the final user count
can be higher. Both named volumes survived. The final backend rebuild and repeated
seed preserved the same sample data and owned media. No volume reset was used as
an ordinary stop/restart mechanism.

## Tests and security review

- Backend build passed locally and in the production image.
- Targeted backend suite: **61 passed**, 15 database integration tests skipped
  because their separate disposable DB environment was not supplied. Tests include
  startup validation, cookie/local-mode restrictions, CUSTOM runtime/SSRF,
  tenant Host authority, same-origin policy, payment encryption, Platform login
  throttling and bootstrap behavior. Loopback-server tests required sandbox access.
- Platform: **151 passed** across 23 test files.
- Restaurant: **19 passed** across 4 test files.
- Vankisi production TypeScript/Vite build passed; it has no test script.
- All app production builds and local/production Compose syntax validation passed.
- Host preserves tenancy; arbitrary forwarded-host spoofing does not select data.
  Proxy IP trust is exact. Local insecure cookies require both explicit local
  mode and the local hostname namespace; public host cookies stay Secure.
- No socket mount, public PostgreSQL, public proxy dashboard, wildcard CORS,
  embedded build secrets, generated migration edits or Cloud-to-LAN calls added.
- Exact production backend image audit: **9 advisories (7 high, 2 moderate)** in
  @nestjs/platform-express, @prisma/config, deepmerge-ts, fast-xml-parser, multer,
  prisma, protobufjs, qs and socket.io-parser. This is dependency-level audit
  output, not proof that every advisory is reachable. Dependencies were not changed;
  triage/remediate before real release.

## Remaining qualification

- Platform Admin bootstrap CLI is compiled and documented, but creation of a new
  privileged account awaits explicit approval following automatic review rejection.
  The on-demand CUSTOM check was proved via its actual service over the database
  and ingress; authenticated Platform-browser operation has not yet been proved.
- Exact Google Chrome run, trusted TLS/cookie behavior with real certificates,
  production redirect/runtime test, provider DNS, registry publishing, managed DB,
  monitoring and production backup/restore exercises remain provider work.
- BOG payment settlement, real provider callbacks, FCM delivery, signed release
  hosting and live POS/Manager/Edge deployment are outside this local website proof.

## Changed file inventory

New files:

- Images: `.dockerignore`, `apps/backend/Dockerfile`,
  `deploy/frontend.Dockerfile`, `deploy/nginx/default.conf`.
- Routing: `compose.yaml`, `compose.local.yaml`, `compose.production.yaml`,
  `deploy/traefik/routes.yml`.
- Environment/bootstrap: `.env.docker.example`, `.env.production.example`,
  `scripts/docker-init.py`, `scripts/docker.sh`,
  `apps/backend/scripts/seed-docker-local.ts`.
- Verification/runtime: `scripts/prove-docker-http.py`,
  `apps/backend/src/health.controller.ts`,
  `apps/backend/src/shared/deployment-config.ts`,
  `apps/backend/src/shared/deployment-config.spec.ts`.
- Canonical runbook and evidence: `docs/DEPLOYMENT.md`, `docs/DEPLOYMENT_PROOF.md`.

Updated files: `.gitignore`, backend `main.ts`, `app.module.ts`, WebsiteAuth
controller, CUSTOM service/runtime checker, and the three relevant agent-state
files (state, map, decisions). No generated contracts, migrations, package
manifests or lockfiles changed. The two pre-existing `dev-origins` edits remain
uncommitted and untouched. A new ignored `.env.docker` was generated locally;
existing application environment files were not read or edited.

The initializer was separately exercised in a temporary directory: six distinct
64-hex secrets, mode 0600, second invocation refused without altering the file.
