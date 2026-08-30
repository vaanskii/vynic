# Deploy — Windows POS machine (always-on local server)

The server runs on the POS machine itself (IP `10.10.10.4`) and stays up across
crashes and reboots via PM2. Postgres runs as a Windows service. Other LAN
devices (manager phone, second terminal) reach it at `http://10.10.10.4:3000`.

---

## 0. Prerequisites (install once)

1. **Node.js LTS** — https://nodejs.org (gives you `node` + `npm`).
2. **PostgreSQL** — https://www.postgresql.org/download/windows/
   - The installer registers Postgres as a Windows service → already always-on.
   - Remember the password you set for the `postgres` user.
3. **Give the machine a fixed IP `10.10.10.4`** (DHCP reservation in the router,
   or a static IP). If this changes, every client pointing at it breaks.

Create the database:
```bash
createdb -U postgres vynic
```

---

## 1. Copy the project + install deps

```bash
cd apps/backend
npm install          # also runs `prisma generate`
```

---

## 2. Create `.env` on THIS machine

Copy `.env.example` to `.env` and fill in real values. Required (server won't
work without these four):

```ini
DATABASE_URL="postgresql://postgres:YOURPASSWORD@localhost:5432/vynic"
JWT_SECRET=<random-long-string>
POS_SYNC_API_KEY=<random-long-string>     # must match the value the POS client sends
COOKIE_ENCRYPTION_KEY=<random-32-char-string>
PORT=3000
NODE_ENV=production
```

Optional (only if you use them): `JWT_REFRESH_SECRET`, `BOG_CLIENT_ID/SECRET`,
`SUPER_ADMIN_*`, `GOOGLE_APPLICATION_CREDENTIALS` (Firebase push — set the
absolute path to the admin SDK json if you want FCM notifications).

Verify before launching:
```bash
npm run check:env        # ✓ all required keys present
```

> Menu, website tables, and the super-admin are seeded automatically on first
> start — nothing to do in `.env` for those.

---

## 3. Apply the database schema

```bash
npx prisma migrate deploy
```

---

## 4. Build

```bash
npm run build            # output → dist/src/main.js
```

---

## 5. Start under PM2 + make it boot-proof

```bash
npm install -g pm2 pm2-windows-startup

pm2 start dist/src/main.js --name vynic-server
pm2 save
pm2-startup install      # ← re-launches the server on every Windows boot
```

That's it — the server is now always-on:
- restarts automatically if it crashes,
- comes back on its own after a reboot / power cut,
- Postgres (Windows service) does the same.

---

## 6. Open the firewall (only for OTHER LAN devices)

The POS app on the same machine works without this. For phones/tablets to reach
it, allow inbound TCP 3000 (run once, as Administrator):

```bash
netsh advfirewall firewall add rule name="vynic-server" dir=in action=allow protocol=TCP localport=3000
```

---

## 7. Point the clients at the server

- **POS app on this machine** → `http://localhost:3000` (or `http://10.10.10.4:3000`)
- **Other LAN devices** → `http://10.10.10.4:3000`

---

## Day-to-day

| Action | Command |
|---|---|
| See status | `pm2 status` |
| Live logs | `pm2 logs vynic-server` |
| Deploy a code change | `npm run serve`  (build + pm2 restart) |
| Stop / start | `pm2 stop vynic-server` / `pm2 start vynic-server` |

---

## Quick sanity check it's working

```bash
pm2 status                                   # vynic-server = online, ↺ low
curl http://localhost:3000/api               # any HTTP response = server alive
```
