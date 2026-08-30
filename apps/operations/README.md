# Vynic POS (Flutter client)

## Run on macOS or iOS (simulator / device)

If the repo is under **iCloud Desktop**, Xcode code signing often fails with
`resource fork, Finder information, or similar detritus not allowed`. Run the
one-time setup (redirects build output to `~/Developer/vynic_pos_build`):

```bash
cd apps/operations
chmod +x scripts/*.sh
./scripts/setup_apple_build.sh
```

Then use the wrapper for `run` / `build` (or configure the same `build-dir` yourself):

```bash
./scripts/flutter.sh run -d macos
./scripts/flutter.sh run -d "iPhone 17"
```

Requirements: Xcode, CocoaPods (`pod`), Flutter stable. Use a `.env` file in this
directory (see `.env` example in repo; not committed).

## Getting Started

See [Flutter documentation](https://docs.flutter.dev/) for general tooling setup.
