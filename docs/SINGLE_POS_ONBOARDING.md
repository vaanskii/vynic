# ერთკოდიანი POS რეგისტრაცია

ეს არის მიმდინარე კოდის პროცესი. Docker/production განახლება და რეალური
რეგისტრაცია ამ შემოწმებაში არ შესრულებულა. ტესტები იყენებს იზოლირებულ მონაცემებს.

## Admin-ისა და მომხმარებლის ნაბიჯები

1. **Platform Admin** ქმნის/ამტკიცებს ორგანიზაციისა და რესტორნის წვდომას და ანიჭებს
   მოქმედ POS + Manager პაკეტს. მფლობელი მოწვევით შედის თავის კაბინეტში.
2. **Admin ან მფლობელი** Devices/POS სექციაში ქმნის ერთჯერად დაკავშირების კოდს.
   პირველი Manager-ის რეგისტრაციის არჩევანი ჩართულია მხოლოდ მაშინ, როცა რესტორანში
   Manager-ის ისტორია არ არსებობს. Admin-ში არჩევანი ჰქვია
   `Include first Manager setup on the Primary POS`; კაბინეტში —
   „პირველი Manager-ის რეგისტრაციაც“.
3. **მომხმარებელი POS-ში** შეიყვანს ამ ერთ კოდს. რესტორანი სერვერის მიერ დგინდება;
   რესტორნის ID ან backend მისამართი production აპში შეყვანას არ საჭიროებს.
4. **მთავარ POS-ზე** ირჩევს სახელს, პირად 4–6-ციფრიან PIN-ს და ადასტურებს მას.
   მეორე აქტივაციის კოდი აღარ არის. საერთო/default PIN არ იქმნება.
5. POS რჩება ინტერნეტთან დაკავშირებული Staff-ის მიღებამდე. მომხმარებელი შედის
   არჩეული PIN-ით და ასრულებს რესტორნის საწყის პარამეტრებს.
6. **Platform Admin** Manager access-ში გასცემს „Create Manager linking code“-ს,
   უკვე აქტიური პირველი Manager-ის შემდეგ. კოდი ვადიანია და ერთ ინსტალაციას აკავშირებს.
   მფლობელი საჭიროებისას Vynic-ის მხარდაჭერას უკავშირდება; კაბინეტს კოდის გაცემის უფლება
   არ აქვს. SUPPORT_READONLY მხოლოდ მეტამონაცემებს კითხულობს.
7. **Manager აპში** შეიყვანს ამ ერთჯერად კოდს, შემდეგ პირადი PIN-ით შედის. კოდი
   Staff-ს/სესიას არ ქმნის და PIN-ს არ ცვლის. სერვერი აბრუნებს მხოლოდ Venue-ს საჯარო
   მეტამონაცემებს; არჩევანი ინახება ამ API origin-ისთვის. აპის restart/logout-ის შემდეგ
   კვლავ მხოლოდ PIN არის საჭირო. ახალი მოწყობილობა ან ადგილობრივი app-data reset
   ახალ ერთჯერად კოდს საჭიროებს.

Manager-ის ახალი კოდი 20 Crockford base32 სიმბოლოა, 30 წუთი მოქმედებს და ერთი
ინსტალაცია იყენებს. იგივე კოდით/ინსტალაციის UUID-ით პასუხის დაკარგვის retry ვადაში
მუშაობს; განსხვავებული UUID უარყოფილია. UUID არის retry identity და არ წარმოადგენს
ავთენტიფიკაციას ან მოწყობილობის attestation-ს. 5 მცდარი verifier მცდელობა კოდს
ბაზაში ამოწურავს. ახალი კოდი აუქმებს ძველ დაუხარჯავ კოდებს; უკვე დაკავშირებული
აპები და Staff სესიები ძალაში რჩება. ძველი დამახსოვრებული Venue არჩევანი/სესიები
თავსებადია; legacy lookup ძველი კლიენტებისთვის დარჩა. ახალი პირველი UI რეალურად
ერთჯერად კოდს იყენებს და reusable რესტორნის კოდს აღარ ითხოვს.

დამატებითი POS-ის კოდში გამორთეთ პირველი Manager-ის არჩევანი. როცა Manager უკვე
არსებობს, ეს არჩევანი აღარ ჩანს. დამატებითი POS ახალ Manager-ს არ ქმნის და
არსებული Primary არ იცვლება. პირველი Manager-ის დასრულებამდე ის მთავარ POS-ს
ელოდება. რეგისტრაცია არ რთავს რამდენიმე POS-ის ერთობლივ ოპერაციულ რეჟიმს;
POS-02.C-ის კვალიფიკაცია ცალკეა.

## აღდგენა და შეცდომები

- არსებულ Manager-ის PIN-ს კაბინეტი ვერ ხედავს/აღადგენს. აღდგენა მხოლოდ
  Vynic Platform Admin-ს შეუძლია არსებული პანელიდან. ჩვეულებრივი შესვლის შემდეგ
  POS/Manager მოქმედი ოპერაციული უფლებები უცვლელია.
- შენახული Device credential-ის 401 უარყოფისას POS აჩვენებს ხელახლა დაკავშირებას.
  გაუქმება ან უარყოფილი მცდელობა ადგილობრივ მონაცემებს/იდენტობას არ შლის.
  ახალი კოდი შესაბამისი Admin/მფლობელის პანელიდან მიიღეთ; ავტომატური reset არ ხდება.
- ვადის გასვლისას მიიღეთ ახალი დაკავშირების კოდი. პირველი Manager-ის ახალი კოდი
  აუქმებს ძველ, დაუხარჯავ პირველი რეგისტრაციის კოდებს. მხოლოდ სწორი Primary Device
  ასრულებს რეგისტრაციას. სხვა მოწყობილობაზე ახალი პირველი კოდი Primary-ს ვერ შეცვლის.
- ერთნაირი წარმატებული მოთხოვნის გამეორება Staff-ს ან Edge ბრძანებას არ აორმაგებს.
  შეცვლილი მონაცემებით გამეორება უარყოფილია. განახლებული POS აუცილებელია: setup
  კოდის ძველი კლიენტით გამოყენება კოდის დახარჯვის წინ HTTP 426-ს აბრუნებს.
- PIN-ის უნიკალურობის პრევენცია არსებულ კონფლიქტს ვერ ასწორებს. თუ აქტიურ Staff-ებს
  უკვე ერთნაირი PIN აქვთ, უფლებამოსილმა ოპერატორმა პანელიდან უნიკალური PIN უნდა დააყენოს.
  ავთენტიფიკაცია კვლავ ზუსტად ერთ აქტიურ შესაბამის Manager-ს მოითხოვს.

## ამ Mac-ზე განახლება და გაშვება

ქვემოთ მოცემული Docker ბრძანება მომხმარებელმა უნდა გაუშვას. ის მიმდინარე checkout-ის
backend და Platform UI-ს ააწყობს; Compose backend-მდე `migrate` dependency-ს უშვებს.
ახალი API-სთვის აუცილებელია დამატებითი მიგრაცია
`20261022120000_single_pos_manager_setup` და
`20261023120000_manager_venue_link` (source-ში 76-ე და 77-ე).

```sh
cd /Users/vaanskii/Developer/vynic
./scripts/docker.sh rebuild backend platform-web
./scripts/docker.sh status
curl -fsS http://api.vynic.localhost/healthz
```

უკვე გაშვებული developer აპის Flutter ტერმინალში გამოიყენეთ `q`, შემდეგ თითო აპი
თავის ტერმინალში თავიდან გაუშვით:

```sh
# POS — ტერმინალი 1
cd /Users/vaanskii/Developer/vynic
python3 apps/operations/tool/dev.py pos
```

```sh
# Manager — ტერმინალი 2
cd /Users/vaanskii/Developer/vynic
python3 apps/operations/tool/dev.py manager
```

თუ shortcuts გირჩევნიათ, თითო zsh ტერმინალში:

```sh
source /Users/vaanskii/Developer/vynic/apps/operations/tool/dev.zsh
vynic-pos
# მეორე ტერმინალში source-ის შემდეგ: vynic-manager
```

ორივე helper კითხულობს მხოლოდ `apps/operations/.env`-ის საჯარო დამატებებს:

```dotenv
VYNIC_ENV=development
VYNIC_API_URL=http://api.vynic.localhost
```

ძველი `.env` ნაწილის ბაიტები და მნიშვნელობები შენარჩუნებულია; დამატებები ცალკე,
`Added by Codex` კომენტარით არის გამოყოფილი. `.env.example`-საც იგივე საჯარო ბლოკი
დაემატა. legacy/private გასაღებები Flutter-ს არ გადაეცემა და `.env` აპის asset არ არის.
`VYNIC_DEV_API_URL` shell override ამ პარამეტრს ცვლის მხოლოდ developer helper-ში.
შენახული developer URL-ის არჩევანი compiled მისამართზე უპირატესია — საჭიროებისას
developer კავშირის კონტროლიდან დააბრუნეთ default-ზე. წარმოების/staging აპი ამ
override-ს უგულებელყოფს და API რედაქტორს არ აჩვენებს.

`.env`/Dart define ცვლილებისათვის სრული ხელახალი გაშვებაა საჭირო: მხოლოდ `R` hot
restart ძველ compiled URL-ს შეინარჩუნებს. უკვე გამოშვებულ აპს ახალი build/update
სჭირდება. `config/production.build.env.example` მხოლოდ საჯარო HTTPS build კონფიგურაციის
ნიმუშია; რეალური production rollout და Windows/mobile release აქ არ მიღებულა.

## ტექნიკური საზღვრები და მტკიცებულება

- `DeviceEnrollment.initialManagerSetup` API-ში default `false`-ია. სერვერი ახლიდან
  ამოწმებს issuer-ს, მოდულებს, Manager-ის ისტორიას, ვადასა და Primary-ს; UI მონაცემები
  უფლებამოსილების წყარო არ არის.
- permission არის Venue-ს, enrollment-ისა და Device-ის კავშირი, composite FK-ებით.
  საჯარო setup ID მხოლოდ retry identity-ა; Device credential ავთენტიფიკაციას არ ცვლის.
- `GET/POST /edge/manager-setup` ძველ activation route-სთან იზიარებს დაცულ completion
  ტრანზაქციასა და throttle-ს. ძველი route Device-bound grant-ს ვერ გამოიყენებს.
- Manager-ის ერთხელ დაკავშირება არსებული per-origin preferences-ით მუშაობს.
  ერთჯერადი Manager კოდი ემატება ამავე per-origin არჩევნის წინ. QR/deep-link
  სისტემა ამ ცვლილებაში არ დამატებულა.
- backend/Platform source build და ორივე macOS debug developer build შემოწმდა.
  აპების გაშვება, რეალური enrollment/activation, Docker update და deployment არ შესრულებულა.
- მიმდინარე შედეგები და შეზღუდვები:
  [POS/config qualification](proofs/SINGLE_POS_SETUP_3463ee40_2026-10-14/qualification.json) და
  [Manager linking qualification](proofs/MANAGER_LINK_3463ee40_2026-10-14/qualification.json).
  OPS-01 კვლავ შეჩერებულია.

## Flutter aggregate-ის გაშვება

ორი რეალური wire ტესტი Go fixture binary-ებს საჭიროებს. `tool/test.py` დროებით
დირექტორიაში აწყობს ორივეს, აწვდის Flutter-ს და დასრულებისას ასუფთავებს. არსებული
Go/Flutter SDK მიუთითეთ, როცა PATH-ზე არ არის:

```sh
cd apps/operations
python3 tool/test.py --go /path/to/go --flutter /opt/homebrew/bin/flutter --no-pub --concurrency=2
```

MENU09 live proof მხოლოდ `tool/prove_menu09_gate.py`-ის გარემოთი უნდა გაეშვას.
Default aggregate მას სხვა dedicated live proof-ების მსგავსად გამოტოვებს; რომელიმე
MENU09 opt-in key-ის მიწოდება ტესტს კვლავ რთავს და არასრული გარემო შეცდომად რჩება.
ეს dedicated proof-ის წარმატება არ არის; მისი ცალკე მიღება კვლავ საჭიროა.
