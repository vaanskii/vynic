# Payment integrations

**Roadmap only. Step 6A changed no payment behaviour and added no schema.**

Two things are called "payments" in this product and they are unrelated domains.
Confusing them would be expensive, so they are separated first.

| | **Restaurant customer payments** | **Vynic SaaS billing** |
|---|---|---|
| Who pays | a diner, for a booking | a restaurant, for Vynic |
| Who is paid | the restaurant | Vynic |
| Provider | the restaurant's merchant account (BOG today) | not chosen; nothing is modelled |
| Modelled in | `WebsiteReservation`, `paymentId`, `paymentStatus` | nowhere — see [PRODUCT_ENTITLEMENTS.md](PRODUCT_ENTITLEMENTS.md) |

This document is about the first column. `Plan` and `VenuePlanAssignment` are
deliberately **not** a billing subscription and never became one.

---

## Where it stands today

Bank of Georgia credentials are process-wide environment configuration:

```
BOG_CLIENT_ID
BOG_CLIENT_SECRET
BOG_AUTH_URL
BOG_API_BASE
```

`BogService` reads them at the process level. There is exactly one merchant
account, and it belongs to the bootstrap Venue. That is correct for a
single-restaurant deployment and **is not the SaaS model** — a second Venue
taking online bookings today would silently take money into the first
restaurant's merchant account.

What *is* already right: **tenant authority for a payment callback comes from the
server-owned booking record, never from the caller.**

```
BOG callback → external_order_id → WebsiteReservation → Venue
```

`external_order_id` is the reservation's own UUID, and the callback signature is
verified against the raw signed bytes before any state is touched. Step 4B2B
made `WebsiteReservation` Venue-owned, so the row that identifies the payment
already identifies the restaurant. No client-supplied `venueId` participates.
See [PUBLIC_TENANCY.md](PUBLIC_TENANCY.md).

That property is what makes the change below tractable: the callback path already
knows which Venue it is in, so it will be able to select that Venue's provider
without any new authority.

---

## Target

```
Venue
  ↓
PaymentIntegration        ← per Venue, per provider, enabled/disabled
  ↓
Provider                  ← BOG, TBC, …
  ↓
Venue-specific credentials
```

Each Venue holds its own `clientId`, provider secret, and whatever other merchant
identifiers the provider requires.

### Requirements

1. **Server-side provider selection by authoritative Venue.** The Venue is
   resolved the way it already is — from the registered host for a browser
   request, from the booking record for a callback — and the provider is chosen
   from it. A client never names a provider or a merchant account.
2. **Secrets encrypted at rest**, or held behind a proper secret-management
   boundary. A provider secret must never be stored as a plaintext user-visible
   value.
3. **Write-only from the outside.** A secret is never returned to a frontend
   client after storage — not to the platform control plane, not to a
   Backoffice, not masked-but-recoverable. Reads answer "is a credential
   configured", never "what is it".
4. **Managed by a trusted platform administrator**, from the control plane
   described in [PLATFORM_CONTROL_PLANE.md](PLATFORM_CONTROL_PLANE.md). This is
   the blocker: there is no platform-admin identity yet, and an endpoint that
   writes merchant credentials without one would be worse than the current
   limitation.
5. **Rotation without downtime**, and a disabled integration that fails closed —
   a Venue whose provider is not configured must not fall through to another
   Venue's credentials, which is exactly what would happen today.
6. **Callbacks keep deriving tenant from server-owned records.** Nothing about
   per-Venue credentials may introduce a client-supplied `venueId` into the
   payment path.

### Not decided

Which providers beyond BOG; whether secrets live in the database encrypted with
an application key or in an external secret manager; how a provider's own
sandbox/production distinction is modelled; refunds and payouts; and how a
restaurant onboards its merchant account.

---

## Why not now

Step 6A is transport. Nothing in the Cloud ↔ Edge boundary needs payment
credentials, so building the schema here would be scope invented for its own
sake — and building it *before* the platform-admin boundary exists would mean
either an unprotected write endpoint or a table nobody can populate.

**Current Vankisi payment behaviour is unchanged.** No environment variable, no
`BogService` call path, no callback handling, and no reservation field was
touched.
