# Proof source and local outputs

Keep maintained scope/results notes, concise portable summaries, original
reference inputs and reproducible verification scripts in Git. Required test
fixtures belong with the tests; they remain part of the source tree.

Generated render passes, screenshots, raw logs, caches, temporary archives,
compiled proof executables and machine-specific QA receipts stay local and are
ignored in the known output locations listed in `.gitignore`. Nothing is deleted.
Older proof notes may name those local files; that does not make them repository
or application dependencies. Local-output references are shown as paths rather
than links to absent Git files.

The rules deliberately preserve runtime assets, fonts/icons, app/website config,
original reference screenshots and experiment source. JSON, PNG, certificates,
`docs/` and `experiments/` are not ignored globally. Existing tracked history is
not removed by ignore rules; removing any historical tracked output requires a
separate scoped decision.
