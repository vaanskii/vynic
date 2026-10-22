# რესურსები და სამუშაო ასლის უცვლელობა

აუდიტი: 2026-09-29, `Asia/Tbilisi`; წყარო `/Users/vaanskii/Developer/vynic`; HEAD `f7bb98247237df0e8c4d11b2b26ab3a0e8c3de5b` + საწყისი WIP.

## შექმნილი და გასუფთავებული რესურსები

| რესურსი | მფლობელობა / მიზანი | საბოლოო მდგომარეობა |
|---|---|---|
| `docs/audits/2026-09-29-f7bb982/` | ამ აუდიტის ახალი ანგარიშები | შენარჩუნებულია, 14 Markdown ფაილი; ისტორიული ანგარიში არ გადაიწერა |
| `/private/tmp/vynic-audit-20260929-f7bb982-180325/` | private logs/hashes/repros/test შედეგები | დროებით შენარჩუნებულია, directory permissions 0700; არ დააკომიტოთ |
| `…/checkout/` | 1,930 ფაილის იზოლირებული ასლი, `.env*`/საიდუმლოებებისა და Git metadata-ის გარეშე | source+lockfiles შენარჩუნებულია; ჰეშებით baseline-ს ემთხვევა |
| `…/checkout/apps/backend/node_modules` | არსებული installation-ის audit-owned copy | წაშლილია; საწყისი installation ხელუხლებელია |
| `…/checkout/apps/platform-web/node_modules` | იგივე | წაშლილია |
| `…/checkout/apps/restaurant-web/node_modules` | იგივე | წაშლილია |
| `…/checkout/apps/vankisi-custom-web/node_modules` | იგივე | წაშლილია |
| `…/checkout/packages/website-client/node_modules` | იგივე | წაშლილია |
| `…/checkout/templates/custom-site/node_modules` | იგივე | წაშლილია |
| copied backend/platform/SaaS/Vankisi/template `dist` directories | ამ აუდიტის build output | ხუთივე წაშლილია; cleanup ზუსტ audit-owned paths-ს იყენებდა |
| `…/pgdata` | ცალკე PostgreSQL cluster-ის `initdb` მცდელობა | shared-memory EPERM; incomplete directory initdb-მ წაშალა; DB/cluster არ შექმნილა |
| IAB tabs `1`, `2` | საჯარო local UI და დაბლოკილი native URL | ორივე დაიხურა; temporary viewport reset; tabs list ცარიელია |
| mock fixtures/repro scripts | synthetic amount/booking/menu/table records | მხოლოდ memory/private files; bank network attempts 0 |
| DB/account/container/volume/worktree | ახალი რესურსი საბოლოოდ არ დასჭირვებია | არცერთი არ შექმნილა; existing რესურსი არ შეცვლილა |

DB creation-მდე exact name-ის შემოწმების წესი ძალაშია. ამ run-ში fresh isolated cluster-იც ვერ შეიქმნა, ამიტომ DB-ის სახელის არჩევა/creation ან არსებულ server-ზე fallback საერთოდ არ მომხდარა. PostgreSQL listener metadata-ის დანახვა DB-ის წაკითხვა არ არის. `vankisi_database`-სთან კავშირი არ დამყარებულა.

მოცულობის შესამცირებლად წაიშალა მხოლოდ private copied dependencies/builds. Repro-ის თავიდან გასაშვებად იმავე locked dependencies-ის იზოლირებული გარემო და backend build ხელახლა მომზადდეს; დარჩენილი script/log/source გამოყენებული სცენარის მტკიცებულებაა, მაგრამ ახლა პირდაპირ runnable installation აღარ არის. მომხმარებლის DB URL ან მიმდინარე customer fixtures არ გამოიყენოთ.

## საწყისი და საბოლოო Git მდგომარეობა

| საზომი | საწყისი | საბოლოო |
|---|---|---|
| branch | `codex/docker-deployment-foundation` | იგივე |
| HEAD | `f7bb98247237df0e8c4d11b2b26ab3a0e8c3de5b` | იგივე |
| modified tracked files | 30 არსებული WIP | იგივე 30, byte-for-byte უცვლელი |
| owner untracked files | `apps/operations/test/live/native_ingress_live_test.dart`, `compose.lan.yaml` | ორივე byte-for-byte უცვლელი |
| audit-created files | 0 | ქვემოთ ჩამოთვლილი 14 ანგარიში |
| საწყისი SHA-256 | 1,937 ფაილი | შეცვლილი/დაკარგული 0 |
| copied source parity | 1,930 ფაილი | განსხვავებული 0 |
| stash / worktrees / branches | read-only inventory | არ შექმნილა, არ წაშლილა, არ შერწყმულა |
| commit/push/deploy | არ მოთხოვნილა | არ შესრულებულა |

საწყისი სრული porcelain: private `original-git-status.txt` და `baseline.json`. საბოლოო: `final-git-status.txt`, `final-integrity-check.json`; cleanup: `cleanup-results.json`. განსხვავება მხოლოდ `?? docs/audits/2026-09-29-f7bb982/`-ია. `git diff --check` pass. ახალი Markdown-ების trailing whitespace/local-link შემოწმებაც pass.

**ერთიანი code revision:** ყველა source finding და isolated test ეხება `f7bb982` + ერთსა და იმავე საწყის WIP-ს; copied source hashes ემთხვევა. Browser-ის running UI ცალკე runtime evidence-ა — მის source/image parity-ს ვერ ვამტკიცებთ. ისტორიული Windows/architecture reports HISTORICAL_REPORT_ONLY references-ია. მომავალში დათარიღებული migration directory-ის სახელი deployment თარიღის დასტური არ არის.

## შექმნილი ანგარიშები

1. `README.md`
2. `SYSTEM_AND_ARCHITECTURE.md`
3. `INVENTORY_MANAGER_UX.md`
4. `INVENTORY_MANAGER_FINDINGS.md`
5. `POS_MENU_EDGE.md`
6. `WEB_COMMERCIAL_SECURITY.md`
7. `UI_UX_AUDIT.md`
8. `SECURITY_AND_RELIABILITY.md`
9. `EVIDENCE_AND_MATRICES.md`
10. `MARKET_BENCHMARK.md`
11. `MASTER_BACKLOG.md`
12. `IMPLEMENTATION_ROADMAP.md`
13. `AUDIT_CHECKLIST.md`
14. `RESOURCE_MANIFEST.md`

Private evidence დროებით ინახება; customer secrets ან live customer records მიზნობრივად არ შეგროვებულა. შემდგომი cleanup მხოლოდ ამ ზუსტად დასახელებულ audit directory-სა და საჭირო არტეფაქტების შენარჩუნებას უნდა დაეყრდნოს; ფართო wildcard ან სხვისი DB-ის drop დაუშვებელია.
