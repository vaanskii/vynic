# Vynic Unlocker

Small internal desktop app for generating signed developer-access tokens for
Vynic POS terminals.

The Unlocker is intentionally separate from `pos_app_client`: customer POS
builds must never include the signing UI or private key handling code.

## Build

From the repository root:

```bash
./tool/build_unlocker.sh
./tool/build_unlocker.sh windows
./tool/build_unlocker.sh macos
```

The built binary carries no private key. At runtime it reads
`secrets/developer_signing_key.json`, verifies that the key matches the public
key shipped in the POS app, and then signs master or per-terminal support
tokens.

Run tests from this directory with:

```bash
flutter test
```
