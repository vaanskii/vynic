# Printer production integration storage evidence

Status: **NOT_DONE**. This packet proves storage/component improvements only.
Production Flutter admission, authenticated LAN/configuration, controller receipts,
cutover/rollback and automatic service lifecycle are not completed. Every required
integrated A–Z case remains NOT_PROVEN_INTEGRATED. Physical tests are NOT_RUN.

- `evidence.json`: final results, before/after, distinct-payload stress, scope gaps.
- `storage-source-manifest.json`: final station/cluster source hashes.
- `changed-source-files.json`: delta from the previous sealed architecture candidate.
- `final-printer-regressions.jsonl`: complete ten-package printer regression run.
- `final-affected.jsonl`: final station/cluster rerun after timing accounting changed.
- `final-race.jsonl`: race selection; its exact earlier source is retained in
  `source-before-timing-fix.json`. Only persistence timing accounting changed.
- `storage-performance-final.jsonl`: final 1/3/10-source, 4/512 KiB comparison.
- `storage-performance-unique.jsonl`: 20 distinct large payloads with 3 voters.
- `windows/`: final hash-verified native Windows ARM64 tests under the interactive
  user. No service registration or valid printer job occurred.
- `retained-artifacts.json`: retained native test binaries outside the checkout.
- `historical-proof-verification.json`: prior sealed packet is unchanged.
- `document-manifest.json`: report/current-state hashes at completion of this run.
- `ARTIFACTS.json`: checksums of this packet, excluding itself.

Earlier logs retain the initial scalar row-decoder reopen failure, the startup
membership race, and intermediate measurements. They are not counted as passing
final evidence. The first VM launcher invocation after startup returned an invalid
argument; checking the current user and retrying succeeded. This was a guest
readiness/launcher failure, not an approval-review rejection.

`collect_evidence.py` validates final-source hashes and successful selections before
rebuilding `evidence.json`. It refuses source drift. Preserve this packet before
new source edits; do not attribute these results to a future source revision.
The older architecture report/packet was not regenerated.

The opted-in Go performance test is `TestStationSoftwarePerformance` with
`VYNIC_STATION_PERF=1`; `VYNIC_STATION_UNIQUE=1` makes payloads distinct. The test
requires loopback sockets, never connects to printers and measures no paper rate.
