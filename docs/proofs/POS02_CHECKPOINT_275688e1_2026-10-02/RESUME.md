# POS-02 persistent checkpoint and resume instructions

Status: **NOT_DONE / UNCOMMITTED / PAUSED_PENDING_USER_DECISIONS**.
Base HEAD: `275688e1e5c5dc0e26e62705ab0c7670cf16d99a`.
Branch at capture: `codex/docker-deployment-foundation`.

This directory is inside the persistent project workspace. It survives removal
of the previous `/tmp/vynic_pos02_zwtj18xz` scratch directory. Its source archive,
patches, evidence, saved commands, and checksum manifests are self-contained;
the `/tmp` paths inside the original proof are historical execution paths.
There is no task commit, and the proof describes an uncommitted candidate.

## Contents and boundaries

- `candidate-source.tar.gz` contains the complete base `apps/operations` and
  `packages/contracts` source, plus only the 32 authored POS-02 source/test/script
  overlays. It also retains the exact isolated build's `macos/Podfile.lock`:
  CocoaPods refreshed only its stale Podfile checksum; no pod or version changed.
  That generated checksum change is excluded from the authored runtime patch
  and was never copied into the shared working tree.
- `candidate-source-sha256.json` records every archived source file. It includes
  tests, assets, locked dependencies, and committed generated models/contracts.
  Build products, SDK/package caches, `.dart_tool`, runtime data, and credentials
  are excluded. Offline dependency resolution regenerates transient files.
- `pos02-runtime.patch` contains exactly 32 authored implementation/test/script
  files plus the runbook. It passes apply-check against untouched base source.
- `pos02-docs-delta.patch` contains only the two task updates to existing WIP
  state/map documents. It passes apply-check against their pre-task contents.
  It is a delta, not a replacement copy containing the unrelated documentation
  WIP. The base/pre-task/final identities are recorded in the manifests.
- `evidence/` holds immutable copies of the final candidate proof, 102-checkpoint
  native proof, raw-log ZIP, and synthetic UI screenshot. `log-entry-sha256.json`
  preserves all raw log identities. `commands/acceptance.json` saves the exact
  65-suite acceptance command; its original Flutter path may need substitution
  with an existing compatible SDK after scratch cleanup.
- `baseline-preservation.json` stores status/hash identities for the original
  267 WIP paths, not their file contents. `handoff-task-paths.json` identifies the
  original 39 task source/documentation/proof paths before this checkpoint.
- `CHECKSUMS.json` hashes every checkpoint file except itself. The read-only
  verifier checks archive members, proof source bindings, logs, and optional
  current working-tree preservation. No original WIP source is in the candidate.

## Current permissions — no owner choice applied

`PrintReconciliation.policy` is a process-local static value initialized to
`unconfigured` on every fresh process. There is no production setting or startup
activation assigning it yet; only disposable tests select a policy. Home/Admin
journals remain readable, but paper confirmation, explicit no-byte retry,
reprint/copy admission, and existing manual copy buttons cannot submit actions.
Automatic initial printing and durable job delivery remain enabled.

One policy currently governs all three reconciliation actions and all labeled
manual copies:

| Candidate policy | Actual authorization |
| --- | --- |
| `unconfigured` | Nobody can act, including manager/admin |
| `administrators` | Persisted Staff with `User.isManager`; normalized `manager` and legacy `admin` qualify, supervisor/waiter do not |
| `printingStaff` | Any uniquely resolved persisted signed-in Staff identity; no separate printing permission bit |

Execution re-reads the stored Staff identity by session username, checks the
current policy/role and exact Venue binding, and requires a reason with at least
three trimmed characters and at most 500 input characters. The stored reason is
trimmed. Paper confirmation is allowed for a current `sent`/`uncertain` attempt;
safe retry is only for `failed` with no bytes attempted. Labeled copies use
frozen content, audited actor/reason and stable request/attempt IDs. A user policy
decision still needs explicit production activation and fresh verification;
the parent recommendation of manager/admin with a reason has not been applied.

## Minimum user prerequisites

1. Exact printer manufacturer/model, firmware, interface, paper width, and model
   coverage; Windows architecture and driver/version if a driver path is used.
2. Kitchen/receipt/bar role mapping and intended host/port per physical device.
   Current software has kitchen/receipt roles; shared sender/bar routing remains
   EDGE-01 scope.
3. A designated noncustomer test device/queue, or an explicit safe maintenance
   window with exact target and authorized paper/cable/power interruption steps.
   Existing live endpoints `10.10.10.5` and `10.10.10.6` remain connected and
   untouched. Their existence is not permission to probe or interrupt them.
4. Confirm who may make marked copies and whether the same manager/admin rule
   should govern paper confirmation and no-byte retry. Current policy couples
   these actions; a requested split would need implementation and tests.
5. An approved native Windows target/test path. Using Parallels requires explicit
   release of the VM hold; an independently approved Windows test machine does
   not release that hold. Do not infer driver acceptance from the successful
   macOS development compile.

Physical acceptance must retain synthetic TEST / DO NOT PREPARE slip counts,
job IDs, attempts/audit, timestamps, model/firmware, and observed/photos of normal
Georgian 80mm output, paper-out/refill, cable/power interruption, POS process
kill/restart, intentional labeled copy/repeated submission, and actual Windows
interface/driver behavior. Follow `docs/POS02_PRINT_DELIVERY.md`. None was run.

## Exact safe resume

1. Read repository `AGENTS.md`, current state, POS-02 criteria, this file, and any
   new parent/user decision. Do not start SEC-05. Until the prerequisites above
   arrive, only verify/preserve this checkpoint and report it.
2. From the project root, perform the read-only verification:

   ```sh
   python3 docs/proofs/POS02_CHECKPOINT_275688e1_2026-10-02/verify_checkpoint.py --check-working-tree
   git rev-parse HEAD
   git branch --show-current
   git stash list --format='%gd %H %gs'
   git diff --cached --name-only
   git status --short
   ```

   Compare HEAD/branch/stash/index with `baseline-preservation.json`. If any
   candidate or original WIP hash differs, stop dependent work and reconcile the
   new ownership/change information. Do not overwrite changed files or reapply
   a patch already present in the shared working tree.
3. If scratch was removed, restore source into a new empty isolated directory:

   ```sh
   POS02_CHECKPOINT="$PWD/docs/proofs/POS02_CHECKPOINT_275688e1_2026-10-02"
   POS02_RESUME_DIR="$(mktemp -d /tmp/vynic-pos02-resume.XXXXXX)"
   tar -xzf "$POS02_CHECKPOINT/candidate-source.tar.gz" -C "$POS02_RESUME_DIR"
   ```

   Verify extracted files against `candidate-source-sha256.json`. This step does
   not replace the shared tree, touch customer data, or require a new checkout.
   Do not copy unrelated WIP into the isolated candidate.
4. After the owner decisions arrive, explicitly implement the chosen production
   policy activation. If runtime changes, regenerate candidate hashes/proofs and
   re-run appropriate tests and independent review. Never represent the frozen
   checkpoint as evidence for later modified source.
5. Use an existing compatible Flutter SDK and an existing package cache. The
   proof used `/private/tmp/vynic-menu02-flutter/bin/flutter`; preserve that fact,
   but do not install anything to recreate it without authorization. In isolated
   `apps/operations`, resolve with `flutter --suppress-analytics pub get --offline
   --enforce-lockfile`. Set `PUB_CACHE` only to an existing compatible cache or an
   authorized owned copy. If SDK/cache are unavailable, report the exact missing
   prerequisite instead of fetching packages or changing the lockfile.
6. Reproduce verification sequentially in that one candidate; do not run test,
   native matrix, and build concurrently because Flutter's native-assets output
   directory is shared. Substitute only the existing SDK executable in the saved
   acceptance argv; preserve its 65 suite arguments. Run Dart analysis with
   `--suppress-analytics analyze lib test`, the saved acceptance command, then:

   ```sh
   python3 tool/prove_pos02_recovery.py --flutter "$POS02_FLUTTER" --output "$POS02_OUTPUT_DIR/native.json"
   "$POS02_FLUTTER" --suppress-analytics build macos --debug --no-pub -t lib/main_pos.dart --dart-define=APP_ROLE=pos --dart-define=VYNIC_ENV=development
   ```

   `POS02_FLUTTER` is the existing SDK executable and `POS02_OUTPUT_DIR` an owned
   proof directory. The native harness permits only synthetic data/endpoints and
   verifies child ancestry before SIGKILL. No live app/device operation is part
   of these commands. Any sandbox approval needed must identify the exact action;
   do not evade a rejected call. Broad discovery's 12 existing failures reproduce
   on untouched HEAD; do not weaken the HTTP guard or add live credentials.
7. Perform only the explicitly approved physical/device tests and separately
   authorized Windows work. Record observations; TCP sent is not paper ACK.
   Keep POS-02 NOT_DONE until required supported-model acceptance and owner
   policy activation are complete. Do not enter SEC-05 while this gate is open.
8. Only then evaluate the user's conditional local-commit authorization. Use a
   clean task-only source export and the isolated runtime patch; never stage the
   entire dirty tree or existing WIP docs. Apply the documentation delta only
   after checking its context and preserving unrelated edits. Do not manipulate
   the stash. No push/deploy/merge/install is authorized. After any permitted
   commit, validate its exact committed runtime, not a WIP overlay, and replace
   candidate state with truthful committed/physical evidence.

This checkpoint records 788 passing acceptance tests / 65 suites, 102 native
SIGKILL checkpoints, clean analysis, successful POS macOS development compile,
and no remaining P1 in focused independent source review. It records no physical
printer or Windows acceptance and grants no new operation permission.
