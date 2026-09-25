# Vynic web

One build serves the public/customer site and the separate Platform Admin host.

```sh
cd apps/platform-web
npm run dev
```

- Public/customer site: http://localhost:5173
- Platform Admin: http://admin.localhost:5173
- Optional branded local aliases: http://vynic.localhost:5173 and
  http://admin.vynic.localhost:5173

Run the backend separately on port 3000 with its existing development configuration
(`cd apps/backend && npm run start:dev`). Vite proxies `/platform`, `/customer`,
and `/media/website-logos` to that backend. No new database or account is required.
Existing operator credentials work; sign in again on the new host.

Admin paths start at `/`: `/login`, `/venues`, `/plans`, `/onboarding`, etc.
The old `/admin` and `/admin/*` addresses return to `/` on the same host;
they do not redirect to the admin subdomain or retain the old destination.

`*.localhost` resolves to loopback in modern browsers. No hosts-file change or
DNS purchase is needed. If a browser/OS cannot resolve it, add these explicit
entries to `/etc/hosts` with administrator privileges:

```text
127.0.0.1 admin.localhost vynic.localhost admin.vynic.localhost
```

The Vite listener binds to `127.0.0.1`; `npm run preview` also supports these
hostnames on port 4173 and proxies to the same local backend. Neither command
is a production server.

Production hosts are `vynic.ge` and `admin.vynic.ge`. See
[admin host setup](../../docs/PLATFORM_ADMIN_HOST.md) for DNS, hosting, API and
session details.
