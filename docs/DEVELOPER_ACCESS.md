# Developer access

The admin panel has two halves. A venue's manager gets the business tools with
their admin PIN. The terminal's plumbing and the destructive tools need a
signed developer token, which only you can produce.

This exists because the app is sold. Once a venue owns the machine, the admin
PIN is theirs, and anything reachable behind it is theirs to break.

## The split

| Manager (admin PIN) | Developer (signed token) |
|---|---|
| პერსონალი, მენიუ, პაკეტები | შეცდომები — error log |
| რეზერვაციები, მაგიდები, ეკრანი | პრინტერები — printer host/port |
| დღის დახურვა | კავშირი — backend URL, sync |
| გაყიდვები, რეპორტები, ფინანსური რეპორტები | დეველოპერი — diagnostics, restore, wipe, PIN recovery |
| აუდიტი | |
| პარამეტრები (backup **create** only) | |

Supervisors are unchanged: staff, reservations, close-day. A token does not
promote whoever is signed in — a supervisor never sees the developer half.

## Opening it

Two doors, both a long press on the **Vynic** wordmark, neither of them marked:

1. **Login screen, top-left wordmark** — no sign-in needed. This is the one that
   matters for support: a venue that has forgotten its admin PIN cannot reach
   the admin panel, and the recovery tool is inside it. Opens the developer
   tools as a screen of their own.
2. **Admin sidebar wordmark** — convenient when you are already inside. Adds the
   developer group to the sidebar: შეცდომები, პრინტერები, კავშირი, დეველოპერი.

Both land on the same four destinations. The standalone screen carries its own
rail so the plumbing sections are reachable without the admin panel around
them.

The gesture is not the security; the signature is. It only keeps the door out of
a curious manager's way.

## Getting a token

Two ways to produce one. Both sign with the same private key, so the output is
identical — pick whichever is in front of you.

### The key tool (a small desktop app)

```bash
./tool/build_unlocker.sh            # builds for this machine
./tool/build_unlocker.sh windows    # builds the Windows executable
```

`pos_app_devtool/` is a Flutter app of its own, deliberately separate from the
POS so that `flutter build windows` in `pos_app_client` can never sweep the
signing tool into a customer's install. The script builds only the tool and
prints where it landed.

Open it and you get: a terminal field (or the **master key** switch), a validity
window, scope checkboxes, and a **Generate token** button with Copy and Save as
file. It reads the private key from `secrets/developer_signing_key.json` — the
binary itself carries no key, so a stray copy of it can sign nothing. If it
cannot find the key it asks you to point at it once and remembers.

It also tells you, before you send anything, whether the loaded key matches the
public key compiled into your shipped builds. A mismatch there is the failure
that otherwise only shows up on a customer's terminal.

### The CLI

```bash
dart run tool/dev_key.dart master
```

`master` is shorthand for `sign --terminal '*' --hours 2160` — a 90-day token
that opens **any** terminal with every scope. This is the one to keep in your
password manager.

For a token bound to one machine:

```bash
dart run tool/dev_key.dart sign --terminal <terminal-id> --hours 8
```

Run either from `pos_app_client/`.

## Master tokens vs per-terminal

**Use a master token for routine work.** No terminal ID, no phone call, no
round-trip: long-press the logo, paste from your password manager, done. Re-sign
it every 90 days.

**Use a per-terminal token** when you want one that cannot travel — handing
access to someone else, or a machine you would rather not issue a general key
for.

The honest trade: while a master token is alive, that one string opens every
terminal you have sold. Per-terminal is tighter. What makes the master token
acceptable is that it expires on its own — a leaked one dies on its date without
you shipping anything.

## The support call

**With a master token in your password manager:** long-press the logo, paste,
work. That is the whole procedure, on any machine, including one you have never
seen.

**When you want a per-terminal token instead:**

1. They long-press the logo. The dialog shows a **Terminal ID**.
2. They read it out, or press Copy and paste it to you.
3. You paste it into the key tool (or `sign --terminal`), pick a window, press
   Generate.
4. Send the token back — over whatever chat you already use, or as a file they
   open with **Load from file**. It is not worth protecting in transit: it opens
   that one terminal, until it expires.
5. They paste it and press Unlock.

Neither path needs them to be signed in.

### At install time

You are already at the machine. Save a token to a file and leave it next to the
app — then the venue never types or pastes anything, they just press **Load from
file**. Send a fresh file when it expires.

### Narrow tokens

Omit `--scopes` (or leave every box ticked in the key tool) and the token grants
everything. For a routine call, grant only
what the job needs:

```bash
dart run tool/dev_key.dart sign --terminal <id> --hours 2 --scopes diagnostics,connection
```

Scopes: `diagnostics`, `connection`, `printers`, `errors`, `backup`, `restore`,
`wipe`, `recovery`. Tools outside the granted set render as locked rather than
disappearing, so it is obvious why a button is missing.

## The credentials

One secret, and it is the whole scheme:

- `secrets/developer_signing_key.json` — the private signing key.

Back it up somewhere you will still have it in three years. Lose it and no
already-installed build can ever be serviced again; every terminal would need a
new build carrying a new public key.

## The keypair

`dart run tool/dev_key.dart keygen` writes the private key to
`secrets/developer_signing_key.json` — gitignored, never shipped, never on a
customer's machine. The public half is pasted into
`lib/core/services/security/developer_public_key.dart` and is the only part
that ships.

A client with the binary can read the public key and learn nothing: verifying a
signature is not the same as producing one.

**Rotating the key invalidates every token for every build already installed.**
A terminal running an old build only accepts tokens signed by the key that
shipped in it, so the new build has to reach a venue before the old key stops
working there. Rotate only if the private key actually leaks.
Two tests catch a half-done rotation on your machine:
`pos_app_client/test/unit/developer_token_roundtrip_test.dart` and
`pos_app_devtool/test/signing_key_test.dart`. Both skip where the private key
is absent.

## What the session is

- **In memory only.** Closing the app relocks the panel. A token used on
  Tuesday is not still open on Friday, even a 90-day one.
- **Time-boxed.** `--hours` is enforced against the wall clock floored at the
  highest time the terminal has ever seen, so winding the machine's clock back
  does not revive an expired token.
- **Bound to one terminal**, unless signed with `*`.
- **Audited.** Unlock, restore, wipe and PIN reset are written to the audit log
  with `developer:<token-id>` as the actor, so a venue reading its own log can
  tell your service call apart from their manager.

## Honest limits

The venue owns the machine and the Hive files. Someone determined can edit the
database directly, and no client-side check can stop that. What this does
guarantee: no sequence of taps inside the app reaches a destructive tool without
a signature you produced, and anything that does happen leaves a record. That is
the achievable goal — accidents become impossible, and tampering becomes
evidence.
