# ქართული ბაზრის შედარება

წვდომის თარიღი: **2026-09-29, Asia/Tbilisi**. ქვემოთ კონკურენტების შესახებ ყველაფერი არის **გამყიდველის საჯარო განცხადება**, არა დამოუკიდებლად გაზომილი საიმედოობა. ანგარიშები არ შექმნილა, კომპანიებს არ დავკავშირებივართ და მათი სისტემები არ შემოწმებულა. „ვერ დადასტურდა“ არ ნიშნავს „არ აქვს“.

## იდენტობა და პირველწყაროები

1. **RestIQ — `restiq.ge`**: ქართული რესტორნის POS-ის ოფიციალური გვერდი; სახელით მსგავსი `restiq.eu` ან `restiqsolutions.com` არ ჩანაცვლებულა. გვერდი აცხადებს offline LAN Hub-ს, BOG/TBC EFT-POS-ს, RS.ge-ს, KDS-სა და დანერგვის/სწავლების მომსახურებას. მითითებული საწყისი Core ფასი იყო **99 GEL/terminal/month**; Pro — 149; ეს ნანახი საჯარო შეთავაზებაა, არა ჩვენი დადასტურებული საბოლოო ღირებულება. [ოფიციალური პროდუქტი](https://restiq.ge/), [POS-ის განმარტება](https://restiq.ge/pos-sistema-restornistvis).
2. **FINA — რესტორნის პროგრამა**: ოფიციალური `fina.ge` გვერდი აღწერს offline POS-ს, შერეულ გადახდას, მაგიდის/შეკვეთის გაყოფა-გაერთიანებას, რეცეპტებს, საწყობის მიღება/დაბრუნება/ჩამოწერას, დადასტურებით გადატანას, წარმოებას, აღწერასა და მომწოდებლის გადახდებს. საჯარო ფასს ამ გვერდიდან არ ვასახელებთ. [ოფიციალური პროდუქტი](https://fina.ge/restornis-programa). RS.ge-ის კონკრეტული სახელმძღვანელო [FINA_RS.pdf](https://fina.ge/manuals/FINA_RS.pdf) სხვა მოდულის მტკიცებულებაა და restaurant-specific integration certification-ად არ ჩაითვალა.
3. **r_keeper + StoreHouse, UCS Georgia**: provider იდენტობა ჩანს UCS-ის საიტზე და მწარმოებლის ქართულ დანერგვის აღწერაში. provider-ის გვერდზე არის საქართველოში R-Keeper 7 + StoreHouse პროექტები; მათი თარიღები/ძველი ვერსიები მიმდინარე მხარდაჭერის ყველა პირობას არ ამტკიცებს. [UCS Georgia](https://ucs.ge/), [საქართველოს დანერგვები](https://ucs.ge/ge/public_html/ახალი-ამბები/), [მწარმოებლის Batumi case](https://rkeeper.ru/blog/korolevskiy-uroven-servisa-r-keeper-v-premium-konditerskoy-batumi/). [StoreHouse-ის ოფიციალური დოკუმენტაცია](https://docs.rkeeper.ru/sh5) search-ში მოიძებნა, მაგრამ გახსნა timeout-ით დასრულდა; მის გამოუკითხავ დეტალებს არ ვეყრდნობით.

## თანაბარი კრიტერიუმები

მოკლე უჯრედები მხოლოდ ზემო წყაროებში პირდაპირ ნახსენებ ფუნქციებს აჯამებს. სამივე კონკურენტის SLA, დატვირთვის ზღვარი, რეალური payment/fiscal certification, სრული TCO და ფიზიკური offline test **დაუდასტურებელია**.

| კრიტერიუმი | RestIQ-ის განცხადება | FINA-ს განცხადება | r_keeper/UCS-ის დადასტურებადი საჯარო ფარგლები | Vynic-ის მიმდინარე მტკიცებულება |
|---|---|---|---|---|
| სერვისის სიჩქარე | mobile→KDS დემო | POS/კიოსკი/KDS | პროფესიონალური POS დანერგვები | ოპერაციები არსებობს; latency benchmark არა |
| offline | LAN Hub | ინტერნეტის გარეშე | ამ ნახული მასალით ზუსტი failure contract უცნობია | Hive ადგილობრივად; durability gaps MENU/POS |
| რამდენიმე ტერმინალი | local hub/mobile | სხვადასხვა location | ქსელის/ობიექტების პროექტები | enrolled Devices ≠ writers; 3/10 BLOCKED |
| split/transfer/cancel | მითითებულია | მითითებულია | granular semantics ამ pass-ში უცნობია | განხორციელებულია; transfer crash gap |
| მარაგი/რეცეპტი | stocktake/წარმოება | receipt/return/transfer/waste/count | StoreHouse bar/kitchen control | receipt/payment/consumption/valuation; transfer/waste/count აკლია |
| Manager mobile | mobile/owner view | ცალკე mobile workflow აქ დაუდასტურებელი | აქ დაუდასტურებელი | რეალური Flutter surface; pending/stale UX პრობლემები |
| printer/KDS | ორივე | ორივე | კონკრეტული hardware აქ დაუდასტურებელი | printer path არსებობს; KDS/ფიზიკური proof არ დადასტურდა |
| onboarding/import/training | import/ადგილზე სწავლება | პროდუქტის demo/contact | ადგილობრივი დანერგვები | enrollment/installer; repeatable restaurant onboarding ჯერ გასაზომია |
| ქართული ენა | ქართული UI | ქართული პროდუქტის ინფორმაცია | ქართულენოვანი provider ინფორმაცია | POS/Manager/owner ka; სრული UI conformance არა |
| ფისკალური/საბანკო ინტეგრაცია | RS.ge, BOG/TBC განცხადება | მოწყობილობები; ზუსტი ბანკი აქ უცნობია | აქ უცნობია | POS manual card recording; website BOG სხვა დომენია |
| reporting | dashboard/analytics | ფინანსები/ანალიტიკა | inventory დანერგვები | Sale ledger/provenance კარგია; COGS/profit ჯერ შეზღუდული |
| website/custom | QR/menu განცხადება | e-menu/QR | bespoke binding აქ უცნობია | shared backend + SAAS/CUSTOM რეალური ძლიერი საფუძველი |
| support/diagnostics | მხარდაჭერის შეთავაზება | vendor support channel | ადგილობრივი integrator | owner support workflow/SLA/restore drill ჯერ გასამართია |
| საოპერაციო სირთულე | მხოლოდ vendor demo | მოდულების დიდი მოცულობა | ცალკე POS/warehouse suite | Manager-ში receipt/payment/recipe ურთიერთობა გაუგებარია; task UX საჭიროა |

ეს არის მოთხოვნების საწყისი ნიშნული და არა რეიტინგი. არც მომხმარებლების რაოდენობა, არც market share, არც „100% offline“ ან „0 შეცდომა“ დადასტურებულ ფაქტად არ გადაიტანოთ მარკეტინგში.

## მინიმალური კონკურენტუნარიანი პროდუქტი

რესტორანი ელოდება სწრაფ შეკვეთას, გასაგებ ანგარიშს, split/transfer/cancel-ის საიმედოობას, სამზარეულოს ბეჭდვას, დღის დასრულებას, ლოკალურ აღდგენას, ქართულ ინტერფეისს და ადამიანურ მხარდაჭერას. მარაგის შეთავაზებისას აუცილებელია განსხვავება მიღებას, გადახდას, შიდა გადაადგილებასა და მოხმარებას შორის. Vynic-ს ბევრი საფუძველი აქვს, მაგრამ დაკარგვის/არასწორი success-ის გზების დახურვა უფრო მნიშვნელოვანია, ვიდრე მეტი switch.

Vynic-ის კონკრეტული ხარვეზებია: production multi-POS authority, სრულფასოვანი warehouse/waste/stocktake, POS acquiring-ის რეალური ინტეგრაციის მტკიცებულება, paid website-ის უსაფრთხოება, reproducible deployment/restore, import/training/support runbook. Inventory-ის მიმდინარე მოდული უნდა გაიყიდოს ზუსტი ფარგლებით და არა სრულ საწყობად.

## მაქსიმუმ სამი გასაზომი უპირატესობა

| შესაძლო უპირატესობა | საზომი და ექსპერიმენტი | მარკეტინგამდე აუცილებელი მტკიცებულება |
|---|---|---|
| აღდგენადი offline POS | 1,000 synthetic order + ყოველი კრიტიკული write boundary-ზე kill; 60-წუთიანი Cloud outage; დაკარგული acknowledged mutation = 0; duplicate settlement = 0 | MENU/POS P0-ები დახურული; Windows/Hive backup→fresh machine proof; limitation matrix გამოქვეყნებული |
| გასაგები ქართულენოვანი მენეჯერის დღიური სამუშაო | 5 ახალი მენეჯერი ასრულებს receipt20kg/payment30/მოძრაობის წაკითხვას ≤5 წუთში, ≥90% სწორად არჩევს stock/debt/cash შედეგს; stale/queued სტატუსს ყველა არჩევს | moderated usability test რეალურ phone-ზე; domain შედეგების API/ledger მტკიცებულება; არა მხოლოდ ახალი ვიზუალი |
| ერთი მართვადი Menu, ორი ტიპის საიტი | synthetic Venue-ის plan→SAAS publish ≤15 წუთი; catalog edit→renderer convergence p95 ≤60 წამი online რეჟიმში; tenant leakage = 0 | stable build/domain identity; canonical retry/durability tests; CUSTOM deployment-ის manual დრო ცალკე, არ დაპირდეთ ავტომატურ DNS/TLS-ს |

ახლა არ ღირს page builder, მრავალი theme, loyalty gamification, AI პროგნოზი, ზოგადი ERP ან microservices rewrite. ავტომატური recurring billing და ახალი delivery integrations მხოლოდ ძირითადი integrity/UX/operations gates-ის შემდეგ. ადგილობრივი ფისკალური ან ბანკის ინტეგრაცია პრიორიტეტული ხდება მაშინ, როცა არჩეული pilot-ის რეალური კონტრაქტი ამას მოითხოვს; შესაბამისი იურიდიული/პროვაიდერული მოთხოვნები ცალკე უნდა დამტკიცდეს.
