# Platform Admin hostname

Platform Admin is served from `https://admin.vynic.ge/`; locally it is
`http://admin.localhost:5173/`. The public/customer site remains at `vynic.ge`
and `http://localhost:5173/`. Both hosts use the same platform-web build, with
separate route trees selected by exact hostname.

## Local development

Start the existing backend on port 3000 using its established local configuration:

```sh
cd apps/backend
npm run start:dev
```

In another terminal:

```sh
cd apps/platform-web
npm run dev
```

Open `http://admin.localhost:5173/`. The anonymous root opens `/login`.
Use your existing PlatformUser credentials. The public owner's login is still
`http://localhost:5173/login` and uses CustomerAccount credentials.

The aliases `vynic.localhost:5173` and `admin.vynic.localhost:5173` also work.
Modern browsers resolve `.localhost` directly to loopback. If local DNS does
not resolve those names, add the explicit loopback entries shown in
`apps/platform-web/README.md`; the application does not edit system hosts files.
The existing Vite server reloads route changes, but restart an already-running
backend if it is not running in watch mode so it receives the new development
origin allowlist.

Vite forwards `/platform/*` and `/customer/*` to port 3000 without removing the
prefix. Keep `VITE_API_BASE_URL` unset/empty to use this same-origin proxy.
If your existing configuration specifies an absolute API URL, it must point to
the intended backend and that backend must allow the frontend origin.
The default development origin policy includes the exact local admin aliases on
5173, 5174 and 4173; production does not enable this development allowance.
`npm run preview` uses port 4173 and the same API proxy after `npm run build`.

## Routes and sessions

| Previous address | New admin address |
| --- | --- |
| `/admin` | `admin.vynic.ge/` |
| `/admin/login` | `admin.vynic.ge/login` |
| `/admin/venues/:id` | `admin.vynic.ge/venues/:id` |
| `/admin/onboarding` | `admin.vynic.ge/onboarding` |
| `/admin/plans` | `admin.vynic.ge/plans` |

The old `/admin` and `/admin/*` URLs return to `/` on their current host.
They do not redirect to the admin subdomain, preserve the old destination, or
retain its query/fragment. On the public host, `/` uses the normal language
selection; on the admin host, `/` requires operator sign-in. Sign-in from a
valid admin path returns to that requested page. Navigation,
sign-out, the public-site link, and owner invitation URLs use the proper host.

Browser session storage is origin-scoped. Tokens are never copied into URLs or
transferred to the other host. Existing operators sign in again once on the new
origin. The public route tree does not mount the Platform auth provider.
Admin retains `/platform/*` PlatformUser authentication and authorization;
CustomerAccount credentials do not become operator credentials.

## Production hosting setup (not deployed by this change)

1. Point the DNS record for `admin.vynic.ge` at the frontend host (A/AAAA or the
   hosting provider's required CNAME). Configure that exact custom domain in the
   hosting provider and provision HTTPS for it. The existing `vynic.ge` public
   domain continues serving the customer site.
2. Build `apps/platform-web` with `npm run build` and serve its `dist` directory
   for both hostnames. Configure history fallback to `index.html` for frontend
   paths, including direct refreshes of `/venues/:id` and `/login`.
3. Proxy `/platform/*` from the admin origin to the existing NestJS backend,
   preserving the path prefix and Authorization header. Configure the API proxy
   before the SPA fallback; an API error must not be replaced by `index.html`.
   Public-host `/customer/*` and media proxies remain necessary for owner flows.
   Alternatively set `VITE_API_BASE_URL` to the intended HTTPS backend when
   building and use its explicit CORS allowlist.
4. Add `https://admin.vynic.ge` to backend `ALLOWED_ORIGINS`, retaining the existing
   permitted origins. The origin is still checked by NestJS when requests arrive
   through a same-origin reverse proxy. Keep backend credentials and JWT secrets
   in the backend environment only.
5. Set `X-Robots-Tag: noindex, nofollow` for the admin host at the hosting layer.
   The admin document also sets a noindex meta tag and its own title/language.
6. Verify login, a direct `/venues/:id` refresh, logout, public-site navigation,
   and an owner invitation link on the real HTTPS domains before rollout.

No DNS records, TLS certificates, production environment files, or live database
rows are modified by the hostname implementation.
