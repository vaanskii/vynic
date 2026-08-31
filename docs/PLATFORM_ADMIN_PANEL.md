# Platform Admin Panel

**Step 7B — complete.** `apps/platform-web/` is the authenticated Vynic
control-plane UI over the Step 7A `/platform/*` API. It is a Vynic operator
surface, not a restaurant Backoffice, Manager screen, or POS settings page.

Companion documents: [PLATFORM_CONTROL_PLANE_API.md](PLATFORM_CONTROL_PLANE_API.md)
and [PLATFORM_CONTROL_PLANE.md](PLATFORM_CONTROL_PLANE.md).

## Application architecture

The existing React 19 + Vite + TypeScript + Tailwind application remains in
place. React Router provides protected application routes and preserves the
existing product site at `/product`, `/en`, and `/ka`. TanStack Query owns
server-state fetching, retry, invalidation, and authoritative refetches after
mutations. Radix Dialog supplies focus-managed modal primitives. Shared
platform components cover the shell, page headers, tables, statuses,
loading/empty/error states, forms, and confirmations.

The authenticated routes are:

```text
/                         Overview
/organizations            Organization directory and creation
/organizations/:id        Organization details and venues
/venues                    Venue directory and creation
/venues/:id                Venue overview
/venues/:id/product        Plan, features, overrides, effective access
/venues/:id/website        WebsiteMode and domains
/venues/:id/devices        Device lifecycle and connection test
/venues/:id/activity       Venue-filtered platform audit
/plans                     Read-only plan catalogue
/features                  Read-only feature catalogue
/devices                   Cross-Venue device inventory
/domains                   Cross-Venue domain inventory
/audit                     Platform audit trail
```

## Authentication and session handling

Login calls `POST /platform/auth/login`. The bearer token and its calculated
expiry are stored together in `sessionStorage` under
`vynic.platform.session.v1`; the password is never stored. A single session
service owns reads, expiry checks, and removal. A single API client supplies the
`Authorization` header and clears the session on `401`.

Startup does not trust token presence. A stored, unexpired token must also pass
`GET /platform/auth/me` before the protected shell renders. Logout and rejected
bootstrap clear the session and TanStack Query cache.

This is a deliberate compatibility choice for the bearer-token API that exists
today. `sessionStorage` limits persistence to the browser tab/session, but the
token remains readable by JavaScript and is therefore exposed if the page has
an XSS vulnerability. It is **not** equivalent to an `HttpOnly`, `Secure`,
same-site cookie. Moving platform authentication to a server-managed cookie
session can be evaluated separately without scattering storage changes across
the UI because all access is behind the session abstraction.

## API client and authority

`src/platform/api.ts` is the only production fetch layer for the control plane.
It owns the API origin, JSON headers/parsing, bearer header, typed errors, DTO
shapes, network-error copy, and unauthorized callback. Page components do not
calculate entitlements, normalize domains, or invent connectivity state. They
render and refetch authoritative backend results.

The Venue page is the primary control surface. It separates basic metadata,
product access, website/domain configuration, devices, and activity. Risky
mutations are confirmed. Plan and feature changes show plan inclusion,
`ENABLED`/`DISABLED` overrides, inheritance, and the backend's effective result
as distinct concepts. Website entitlement, configured `WebsiteMode`, effective
mode, and consistency remain independent and an inconsistency is shown rather
than corrected in the browser.

## Device credentials and POS provisioning

Device creation and credential rotation return a raw credential once. It exists
only in the one-time credential dialog's React state. The normal Device read
path has no raw credential or hash, and the UI has no “view existing
credential” action. Dismissing the dialog removes the raw value from the active
component state; a lost credential must be rotated.

The Flutter POS provisioning reader consumes a plain-text file named exactly:

```text
edge_device_provision.txt
```

Its content is one raw credential followed by a newline:

```text
vynic-device-v1.<device-uuid>.<secret>\n
```

The POS trims the file, stores the credential, and deletes the one-shot drop
file. The Admin Panel download produces this exact filename and content; it
does not include IDs, JSON, labels, or any other secret.

## Edge connection test

“Send connection test” calls `POST /platform/venues/:venueId/test-command` and
queues the API's fixed `NOOP`. The UI reports **Command queued**. It does not
claim that the POS connected or executed the command because Step 7A exposes no
command-result readback route. Arbitrary command types and payloads remain
unavailable, and the Step 6C command migration remains deferred.

## Environment and deployment prerequisites

### Local development

If the frontend and backend are served from separate local origins, build/run
the frontend with:

```text
VITE_API_BASE_URL=http://127.0.0.1:3000
```

If they are reverse-proxied behind the same origin, omit it. The backend already
allows the development Vite origins `http://localhost:5173` and
`http://127.0.0.1:5173`.

The backend still requires its existing `DATABASE_URL` and `JWT_SECRET`. Create
the first operator manually from `apps/backend/`:

```bash
npm run platform-admin:create -- --email <email> --name "<name>"
```

The script prompts for the password and does not create or reset an account on
frontend startup.

### Production

For a separately hosted frontend set the build-time value:

```text
VITE_API_BASE_URL=https://<backend-origin>
```

Configure the backend runtime with:

```text
ALLOWED_ORIGINS=https://<platform-admin-origin>
PLATFORM_JWT_SECRET=<strong-random-platform-only-secret>
```

`PLATFORM_JWT_SECRET` is optional for compatibility because audience, principal
type, and subject lookup already separate the token; it is strongly recommended
in production for key separation. Keep the existing required `DATABASE_URL` and
`JWT_SECRET`. Serve both origins over HTTPS and configure SPA history fallback
to `index.html`. No provider deployment was performed in Step 7B.

## Deferred work

Restaurant Backoffice, restaurant roles/permissions, device self-service,
support roles, billing, payment credentials, generic/custom restaurant website
runtime, signed offline commercial licensing, Manager Cloud migration, and the
Step 6C legacy command migration remain separate phases. Generated shared API
contracts and route-level bundle splitting may also be considered later; 7B
uses focused interfaces derived from the implemented Step 7A DTOs.
