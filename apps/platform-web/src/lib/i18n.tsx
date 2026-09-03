import { createContext, useContext, useEffect, useMemo, type ReactNode } from "react";
import { useLocation } from "react-router-dom";

export type Locale = "en" | "ka";

export const LOCALE_STORAGE_KEY = "vynic-site-locale";

export type SiteCopy = {
  nav: { product: string; floorPlan: string; reservations: string; manager: string; contact: string; bookDemo: string; languageLabel: string; serviceReady: string; homeLabel: string; openNav: string; closeNav: string };
  hero: { eyebrow: string; title: string; body: string; seeScreens: string; facts: string[] };
  capabilities: Array<{ number: string; label: string; body: string }>;
  floor: { title: string; body: string };
  product: { eyebrow: string; title: string; body: string; shiftFlow: string; tour: Array<{ label: string; title: string; body: string }>; liveStatus: string; states: string[] };
  reservations: { title: string; body: string; steps: Array<{ title: string; body: string }> };
  manager: { title: string; body: string; roleTitle: string; roleBody: string; closeTitle: string; closeBody: string; practicalTitle: string; points: string[] };
  local: { title: string; body: string; items: Array<{ title: string; body: string }> };
  form: { kicker: string; title: string; body: string; steps: Array<{ number: string; title: string; body: string }>; name: string; restaurant: string; phone: string; email: string; message: string; placeholder: string; requiredError: string; success: string; sending: string; note: string };
  editor: Record<string, string>;
  screen: Record<string, string>;
};

const en: SiteCopy = {
  nav: { product: "Product", floorPlan: "Floor Plan", reservations: "Reservations", manager: "Manager App", contact: "Contact", bookDemo: "Book a Demo", languageLabel: "KA", serviceReady: "SERVICE READY", homeLabel: "Vynic home", openNav: "Open navigation", closeNav: "Close navigation" },
  hero: { eyebrow: "Restaurant operations POS", title: "Restaurant POS for the room as it runs", body: "Run tables, orders, reservations, payments, and manager visibility from one offline-first system that follows the shift.", seeScreens: "See Screens", facts: ["Floor first", "Offline ready", "GEL native"] },
  capabilities: [
    { number: "01", label: "Offline service", body: "Keep taking orders when the connection drops, then sync service state when it returns." },
    { number: "02", label: "Business-day close", body: "Close the operating day with open-table checks, Z report context, and GEL totals." },
    { number: "03", label: "Visual floor plan", body: "Run the room from actual tables, merged parties, reservations, and live status." },
    { number: "04", label: "Reservation handling", body: "Keep guest details, table context, and reservation notes together for staff." },
    { number: "05", label: "Manager mobile", body: "Give owners a smaller live view for tables, reservations, and day movement." },
    { number: "06", label: "Audit trail", body: "Keep cancel, close, staff, and manager actions attached to the restaurant record." },
    { number: "07", label: "Georgian interface", body: "Let the floor team work in Georgian across POS and manager screens." },
  ],
  floor: { title: "Draw the floor once. Run service from it every day.", body: "Set up tables, room objects, and service zones in one clear floor editor. The same layout becomes the working surface for every shift." },
  product: {
    eyebrow: "Product experience", title: "One system from the first table to close of day.", body: "Follow one real POS shift through the live floor, active check, order editor, payment choice, and close-day controls.", shiftFlow: "SHIFT FLOW", liveStatus: "Table 8 ·", states: ["Available", "Reserved", "Occupied"],
    tour: [
      { label: "FLOOR PLAN", title: "Read the room before opening a check", body: "Free and occupied tables, floor objects, service counts, and the next reservation stay visible together." },
      { label: "ACTIVE TABLE", title: "See the whole check before acting", body: "Reservation context, line items, service, totals, print actions, and table controls remain attached to one order." },
      { label: "ORDER ENTRY", title: "Edit the order without losing context", body: "English menu categories, menu prices, quantities, service, and the running total stay in one working view." },
      { label: "PAYMENT", title: "Choose the payment path clearly", body: "Cash, Bank POS, and split payment appear over the same check so the waiter can close with confidence." },
      { label: "DAY CLOSE", title: "Know what blocks close before pressing it", body: "Revenue, Z report, open tables, unfinished takeaways, and reservation blockers stay visible before the business date moves." },
    ],
  },
  reservations: { title: "Online reservations arrive as restaurant work.", body: "Guests book online, attach preorder context when needed, and staff manage the reservation in Vynic.", steps: [{ title: "Guest selects a table", body: "The booking flow starts with date, table, and time selection from the restaurant website." }, { title: "Preorder can be attached", body: "Banquet or event-style reservations can carry selected menu context when that flow is used." }, { title: "Staff manage it in Vynic", body: "Guest details, table context, and preorder notes reach the POS side for staff to review and manage." }] },
  manager: { title: "Manager visibility is connected to the POS.", body: "Staff roles, day close, reservations, and guarded manager actions belong to the same restaurant state.", roleTitle: "Role control", roleBody: "Managers, supervisors, waiters, and PIN codes are visible from the manager center.", closeTitle: "Close-day guardrails", closeBody: "Vynic warns about open tables before close-day actions move the business date.", practicalTitle: "Practical visibility", points: ["Staff roles and PINs", "Close-day warnings", "Reservations", "Orders and totals", "Guarded manager actions"] },
  local: { title: "Built around Georgian restaurant operation.", body: "Vynic is shaped around the local floor, payment, language, service fee, banquet, and close-day details owners actually handle.", items: [{ title: "Georgian interface", body: "The operating language can match the team on the floor." }, { title: "GEL and service fee", body: "Totals, fee context, and Georgian restaurant payment habits stay visible in the workflow." }, { title: "Local payment context", body: "Cash, Bank POS, GEL totals, and service fee context stay visible in the workflow." }, { title: "Banquet and event tables", body: "Merged tables, preorder context, and event-style service can stay tied to the floor." }, { title: "Close-day after late service", body: "Open-table warnings, Z report, revenue, and the business date stay together before the day closes." }] },
  form: { kicker: "Demo request", title: "See how Vynic would run your restaurant floor.", body: "Tell us about the restaurant, and the demo can focus on tables, reservations, payments, and close-day.", steps: [{ number: "01", title: "Your room", body: "Floor plan, live table state, and larger parties." }, { number: "02", title: "Your shift", body: "Orders, payments, reservations, and close-day." }, { number: "03", title: "Your close", body: "Business-day checks, totals, and manager visibility." }], name: "Name", restaurant: "Restaurant name", phone: "Phone", email: "Email", message: "Message", placeholder: "Tell us about your floor, reservations, or payment setup.", requiredError: "Name, restaurant name, and phone are required.", success: "Demo request captured. The walkthrough can be shaped around the way your team works.", sending: "Sending", note: "We’ll tailor the walkthrough to your floor, reservations, and close-day rhythm." },
  editor: { floor: "Floor", ready: "Ready to edit", unsaved: "Unsaved changes", undo: "Undo", redo: "Redo", grid: "Grid", snap: "Snap", preview: "Preview", editLayout: "Edit layout", save: "Save", saved: "Saved", selection: "Selection", selectMove: "Select / move", tables: "Tables", table: "Table", roundTable: "Round table", booth: "Booth", communal: "Communal", rectangle: "Rectangle", square: "Square", round: "Round", structure: "Structure", wall: "Wall", divider: "Divider", entrance: "Entrance", objects: "Objects", bar: "Bar", stage: "Stage", stairs: "Stairs", annotation: "Annotation", zone: "Zone", label: "Label", click: "Click", place: "Click to place", tableAdded: "Table added", editName: "edit its name in the inspector", available: "Available", selected: "Selected", dragHelp: "Drag to move · Shift-click for multi-select · Delete to remove", floorName: "Floor name", canvas: "Canvas", width: "Width", height: "Height", canvasRatio: "Canvas ratio", gridStep: "Grid step", seats: "Seats", editRoom: "Edit the room", editRoomBody: "Choose an object on the left, then click the canvas to place it. Drag anything to refine the room.", objectsSelected: "objects selected", alignHelp: "Align the selected objects from the toolbar, or use the keyboard to nudge them together.", duplicate: "Duplicate", delete: "Delete", shape: "Shape", rotation: "Rotation", transform: "Transform", barSeat: "Bar seat", copy: "copy", chooseTable: "Choose Table to add your first table", clickFloor: "Click anywhere on the floor to place it", autoName: "Table added" },
  screen: { pos: "Vynic POS", tables: "Tables", count: "Count", takeaways: "Takeaways", reservation: "Reservations", settings: "Settings", floorOne: "Floor 1", floorTwo: "Floor 2", free: "Available", occupied: "Occupied", reserved: "Reserved", online: "Online", onDuty: "On duty", serviceNow: "Service right now", needsAttention: "Needs attention", allGood: "Everything is in order", nextReservations: "Next reservations", all: "All", forTable: "For the table", tableActions: "Table actions", activeTable: "Active table", status: "Status", opened: "Opened", duration: "Duration", total: "Total", order: "Order", positions: "items", reservationContext: "Reservation context", guest: "Guest", confirmed: "Confirmed", newItem: "New item", splitMerge: "Split / merge", print: "Print", payable: "Payable", service: "Service", payment: "Payment", orderEditor: "Order editor", searchMenu: "Search the menu", categories: "Categories", coldDishes: "Cold dishes", hotDishes: "Hot dishes", sauces: "Sauces", soups: "Soups", bakery: "Bakery", dumplings: "Dumplings", grill: "From the grill", seafood: "Seafood", dessert: "Dessert", addToBooking: "Add to booking", availablePreorder: "Available for preorder", attachedTo: "Attached to", preorderTotal: "Preorder total", managerCenter: "Manager center", managerView: "Manager view", tonight: "Tonight", bookings: "Bookings", gelToday: "GEL today", openChecks: "Open checks", nextReservation: "Next reservation", control: "Control", guestFlow: "Guest flow", reserveTable: "Reserve a table", select: "Select", step: "Step 02 / 03", team: "Team", roles: "Roles", alert: "Alert", fullAccess: "Full access", floorClose: "Floor + close", posFloor: "POS floor", daySummary: "Day summary", sales: "Total sales", cash: "Cash", bankPos: "Bank POS", zReport: "Z report", closeDay: "Close day", checkBeforeClose: "Check before close", openTable: "Open table", unfinishedTakeaway: "Unfinished takeaway", zReportReady: "Z report ready", noPrinterErrors: "No printer errors detected", good: "Good", walkIn: "Walk-in", guestCount: "guests", seats: "seats", placeLabel: "Place", georgianMenu: "Georgian", englishMenu: "English" },
};

const ka: SiteCopy = {
  nav: { product: "პროდუქტი", floorPlan: "სართულის გეგმა", reservations: "რეზერვაციები", manager: "მენეჯერის აპი", contact: "კონტაქტი", bookDemo: "დემო დაჯავშნე", languageLabel: "EN", serviceReady: "სერვისი მზადაა", homeLabel: "Vynic-ის მთავარი", openNav: "ნავიგაციის გახსნა", closeNav: "ნავიგაციის დახურვა" },
  hero: { eyebrow: "რესტორნის ოპერაციების POS", title: "რესტორნის POS ოთახის რეალური მუშაობისთვის", body: "მართე მაგიდები, შეკვეთები, რეზერვაციები, გადახდები და მენეჯერის ხედვა ერთი offline-first სისტემიდან, რომელიც ცვლას მიჰყვება.", seeScreens: "ეკრანების ნახვა", facts: ["ჯერ სართული", "ოფლაინ მზადაა", "GEL-ზე მორგებული"] },
  capabilities: [{ number: "01", label: "ოფლაინ სერვისი", body: "მიიღე შეკვეთები კავშირის გაწყვეტისასაც და დაბრუნებისას სერვისის მდგომარეობა დაასინქრონე." }, { number: "02", label: "სამუშაო დღის დახურვა", body: "დახურე სამუშაო დღე ღია მაგიდების შემოწმებით, Z რეპორტით და GEL ჯამებით." }, { number: "03", label: "სართულის გეგმა", body: "მართე დარბაზი რეალური მაგიდებით, გაერთიანებული სტუმრებით, რეზერვაციებით და ცოცხალი სტატუსით." }, { number: "04", label: "რეზერვაციების მართვა", body: "სტუმრის დეტალები, მაგიდა და შენიშვნები ერთ სამუშაო სივრცეში შეინახე." }, { number: "05", label: "მენეჯერის მობილური", body: "მფლობელებს მაგიდების, რეზერვაციებისა და დღის მოძრაობის მოკლე ცოცხალი ხედვა მიეცი." }, { number: "06", label: "აუდიტის კვალი", body: "გაუქმება, დახურვა, თანამშრომელი და მენეჯერის მოქმედებები რესტორნის ჩანაწერს მიაბი." }, { number: "07", label: "ქართული ინტერფეისი", body: "დარბაზის გუნდმა POS და მენეჯერის ეკრანები ქართულად გამოიყენოს." }],
  floor: { title: "სართული ერთხელ დახაზე. სერვისი ყოველდღე მისგან მართე.", body: "მოაწყვე მაგიდები, ოთახის ობიექტები და სერვისის ზონები ერთ მკაფიო რედაქტორში. იგივე გეგმა ყოველი ცვლის სამუშაო ზედაპირი გახდება." },
  product: { eyebrow: "პროდუქტის გამოცდილება", title: "ერთი სისტემა პირველი მაგიდიდან დღის დახურვამდე.", body: "გაჰყევი ერთ რეალურ POS ცვლას ცოცხალ სართულზე, აქტიურ ჩეკზე, შეკვეთის რედაქტორზე, გადახდასა და დღის დახურვაზე.", shiftFlow: "ცვლის ნაკადი", liveStatus: "მაგიდა 8 ·", states: ["თავისუფალი", "დაჯავშნილი", "დაკავებული"], tour: [{ label: "სართულის გეგმა", title: "ჩეკის გახსნამდე ოთახი დაინახე", body: "თავისუფალი და დაკავებული მაგიდები, ობიექტები, სერვისის რაოდენობები და შემდეგი რეზერვაცია ერთად ჩანს." }, { label: "აქტიური მაგიდა", title: "მოქმედებამდე მთელი ჩეკი ნახე", body: "რეზერვაციის კონტექსტი, პოზიციები, სერვისი, ჯამები და მაგიდის კონტროლები ერთ შეკვეთას მიჰყვება." }, { label: "შეკვეთის დამატება", title: "კონტექსტის დაკარგვის გარეშე შეცვალე შეკვეთა", body: "ქართული კატეგორიები, მენიუს ფასები, რაოდენობები, სერვისი და ჯამი ერთ სამუშაო ხედში რჩება." }, { label: "გადახდა", title: "გადახდის გზა მკაფიოდ აირჩიე", body: "ნაღდი, Bank POS და გაყოფილი გადახდა იმავე ჩეკზე ჩანს, რომ ოფიციანტმა თავდაჯერებით დახუროს." }, { label: "დღის დახურვა", title: "დახურვამდე იცოდე რა გაჩერებს", body: "შემოსავალი, Z რეპორტი, ღია მაგიდები და რეზერვაციის ბლოკერები თარიღის შეცვლამდე ჩანს." }] },
  reservations: { title: "ონლაინ რეზერვაცია რესტორნის სამუშაოდ იქცევა.", body: "სტუმარი ონლაინ ჯავშნის, საჭიროებისას წინასწარ შეკვეთას ამატებს და გუნდი რეზერვაციას Vynic-ში მართავს.", steps: [{ title: "სტუმარი მაგიდას ირჩევს", body: "დაჯავშნა ვებსაიტზე თარიღის, მაგიდისა და დროის არჩევით იწყება." }, { title: "წინასწარი შეკვეთა ემატება", body: "ბანკეტისა და ღონისძიების რეზერვაციას საჭიროებისას მენიუს არჩეული კონტექსტი მოჰყვება." }, { title: "გუნდი Vynic-ში მართავს", body: "სტუმრის დეტალები, მაგიდის კონტექსტი და წინასწარი შეკვეთის შენიშვნები POS-ში გადადის." }] },
  manager: { title: "მენეჯერის ხედვა POS-ს უკავშირდება.", body: "თანამშრომლების როლები, დღის დახურვა, რეზერვაციები და დაცული მოქმედებები ერთი რესტორნის მდგომარეობის ნაწილია.", roleTitle: "როლების კონტროლი", roleBody: "მენეჯერები, სუპერვაიზერები, ოფიციანტები და PIN-კოდები მენეჯერის ცენტრში ჩანს.", closeTitle: "დღის დახურვის დაცვა", closeBody: "Vynic ღია მაგიდებზე გაფრთხილებს, სანამ დღის დახურვა სამუშაო თარიღს შეცვლის.", practicalTitle: "პრაქტიკული ხედვა", points: ["თანამშრომლების როლები და PIN-ები", "დღის დახურვის გაფრთხილებები", "რეზერვაციები", "შეკვეთები და ჯამები", "დაცული მენეჯერის მოქმედებები"] },
  local: { title: "შექმნილია ქართული რესტორნის მუშაობისთვის.", body: "Vynic ითვალისწინებს ადგილობრივ სართულს, გადახდებს, ენას, სერვისის საფასურს, ბანკეტსა და დღის დახურვას.", items: [{ title: "ქართული ინტერფეისი", body: "სამუშაო ენა დარბაზის გუნდს მოერგება." }, { title: "GEL და სერვისის საფასური", body: "ჯამები, საკომისიოს კონტექსტი და ქართული გადახდის ჩვევები სამუშაო პროცესში ჩანს." }, { title: "ადგილობრივი გადახდები", body: "ნაღდი, Bank POS, GEL ჯამები და სერვისის საფასური ერთ ხედში რჩება." }, { title: "ბანკეტი და ღონისძიების მაგიდები", body: "გაერთიანებული მაგიდები, წინასწარი შეკვეთა და ღონისძიების სერვისი სართულს მიჰყვება." }, { title: "გვიანი სერვისის შემდეგ დახურვა", body: "ღია მაგიდები, Z რეპორტი, შემოსავალი და სამუშაო თარიღი დახურვამდე ერთად ჩანს." }] },
  form: { kicker: "დემოს მოთხოვნა", title: "ნახე, როგორ მართავს Vynic შენს რესტორნის სართულს.", body: "მოგვიყევი რესტორანზე და დემო მაგიდებზე, რეზერვაციებზე, გადახდებსა და დღის დახურვაზე მოვარგებთ.", steps: [{ number: "01", title: "შენი ოთახი", body: "სართულის გეგმა, მაგიდების ცოცხალი მდგომარეობა და დიდი ჯგუფები." }, { number: "02", title: "შენი ცვლა", body: "შეკვეთები, გადახდები, რეზერვაციები და დღის დახურვა." }, { number: "03", title: "შენი დახურვა", body: "სამუშაო დღის შემოწმებები, ჯამები და მენეჯერის ხედვა." }], name: "სახელი", restaurant: "რესტორნის სახელი", phone: "ტელეფონი", email: "ელფოსტა", message: "შეტყობინება", placeholder: "მოგვიყევი სართულის, რეზერვაციებისა და გადახდების შესახებ.", requiredError: "სახელი, რესტორნის სახელი და ტელეფონი აუცილებელია.", success: "დემოს მოთხოვნა მიღებულია. ჩვენ მას თქვენი გუნდის მუშაობას მოვარგებთ.", sending: "იგზავნება", note: "დემოს თქვენს სართულს, რეზერვაციებსა და დღის დახურვის რიტმს მოვარგებთ." },
  editor: { floor: "სართული", ready: "რედაქტირებისთვის მზადაა", unsaved: "შეუნახავი ცვლილებები", undo: "უკან", redo: "გამეორება", grid: "ბადე", snap: "მიბმა", preview: "გადახედვა", editLayout: "გეგმის რედაქტირება", save: "შენახვა", saved: "შენახულია", selection: "არჩევა", selectMove: "არჩევა / გადაადგილება", tables: "მაგიდები", table: "მაგიდა", roundTable: "მრგვალი მაგიდა", booth: "ბოქსი", communal: "საერთო მაგიდა", rectangle: "მართკუთხედი", square: "კვადრატი", round: "მრგვალი", structure: "სტრუქტურა", wall: "კედელი", divider: "გამყოფი", entrance: "შესასვლელი", objects: "ობიექტები", bar: "ბარი", stage: "სცენა", stairs: "კიბე", annotation: "ანოტაცია", zone: "ზონა", label: "წარწერა", click: "დააჭირე", place: "დასასმელად დააჭირე", tableAdded: "მაგიდა დაემატა", editName: "სახელი ინსპექტორში შეცვალე", available: "ხელმისაწვდომი", selected: "არჩეული", dragHelp: "გადაადგილება · Shift-დაჭერა მრავალარჩევისთვის · Delete წასაშლელად", floorName: "სართულის სახელი", canvas: "ტილო", width: "სიგანე", height: "სიმაღლე", canvasRatio: "ტილოს შეფარდება", gridStep: "ბადის ნაბიჯი", seats: "ადგილები", editRoom: "ოთახის რედაქტირება", editRoomBody: "მარცხნივ აირჩიე ობიექტი, შემდეგ ტილოზე დააჭირე მის დასასმელად. ოთახის დასახვეწად ობიექტები გადაადგილე.", objectsSelected: "ობიექტია არჩეული", alignHelp: "არჩეული ობიექტები ხელსაწყოთა ზოლიდან გაასწორე ან კლავიატურით ერთად გადაადგილე.", duplicate: "დუბლირება", delete: "წაშლა", shape: "ფორმა", rotation: "ბრუნვა", transform: "ტრანსფორმაცია", barSeat: "ბარის ადგილი", copy: "ასლი", chooseTable: "აირჩიე მაგიდა პირველი მაგიდის დასამატებლად", clickFloor: "ტილოზე ნებისმიერ ადგილას დააჭირე", autoName: "მაგიდა დაემატა" },
  screen: { pos: "Vynic POS", tables: "მაგიდები", count: "დათვლა", takeaways: "გატანები", reservation: "რეზერვაციები", settings: "პარამეტრები", floorOne: "სართული 1", floorTwo: "სართული 2", free: "თავისუფალი", occupied: "დაკავებული", reserved: "დაჯავშნილი", online: "ონლაინი", onDuty: "მორიგე", serviceNow: "სერვისი ახლა", needsAttention: "ყურადღებას საჭიროებს", allGood: "ყველაფერი წესრიგშია", nextReservations: "შემდეგი რეზერვაციები", all: "ყველა", forTable: "მაგიდისთვის", tableActions: "მაგიდის მოქმედებები", activeTable: "აქტიური მაგიდა", status: "სტატუსი", opened: "გახსნა", duration: "ხანგრძლივობა", total: "ჯამი", order: "შეკვეთა", positions: "პოზიცია", reservationContext: "რეზერვაციის კონტექსტი", guest: "სტუმარი", confirmed: "დადასტურებული", newItem: "ახალი პოზიცია", splitMerge: "გაყოფა / გაერთიანება", print: "ბეჭდვა", payable: "გადასახდელი", service: "სერვისი", payment: "გადახდა", orderEditor: "შეკვეთის რედაქტირება", searchMenu: "მოძებნე მენიუში", categories: "კატეგორიები", coldDishes: "ცივი კერძები", hotDishes: "ცხელი კერძები", sauces: "სოუსები", soups: "წვნიანები", bakery: "ცომეული", dumplings: "ხინკალი", grill: "კერძი მაყალზე", seafood: "ზღვის პროდუქტები", dessert: "დესერტი", addToBooking: "დაჯავშნაში დამატება", availablePreorder: "წინასწარი შეკვეთისთვის ხელმისაწვდომი", attachedTo: "მიბმულია", preorderTotal: "წინასწარი შეკვეთის ჯამი", managerCenter: "მენეჯერის ცენტრი", managerView: "მენეჯერის ხედვა", tonight: "დღეს საღამოს", bookings: "ჯავშნები", gelToday: "GEL დღეს", openChecks: "ღია ჩეკები", nextReservation: "შემდეგი რეზერვაცია", control: "კონტროლი", guestFlow: "სტუმრის ნაკადი", reserveTable: "მაგიდის დაჯავშნა", select: "არჩევა", step: "ნაბიჯი 02 / 03", team: "გუნდი", roles: "როლები", alert: "გაფრთხილება", fullAccess: "სრული წვდომა", floorClose: "სართული + დახურვა", posFloor: "POS სართული", daySummary: "დღის შეჯამება", sales: "სულ გაყიდვები", cash: "ნაღდი", bankPos: "Bank POS", zReport: "Z რეპორტი", closeDay: "დღის დახურვა", checkBeforeClose: "დახურვამდე შეამოწმე", openTable: "ღია მაგიდა", unfinishedTakeaway: "დაუსრულებელი გატანა", zReportReady: "Z რეპორტი მზადაა", noPrinterErrors: "პრინტერის შეცდომა არ არის", good: "კარგია", walkIn: "Walk-in", guestCount: "სტუმარი", seats: "ადგილი", placeLabel: "ადგილი", georgianMenu: "ქართული", englishMenu: "ინგლისური" },
};

// The Georgian copy is intentionally reviewed as product language, rather than
// as a literal word-for-word translation. Keep the base dictionary above easy
// to scan while making the customer-facing phrasing natural here.
const polishedKa: SiteCopy = {
  ...ka,
  nav: {
    ...ka.nav,
    bookDemo: "დემო დაჯავშნე",
    homeLabel: "Vynic-ის მთავარი გვერდი",
  },
  hero: {
    ...ka.hero,
    title: "რესტორნის POS რეალური სამუშაო პროცესისთვის",
    body: "მართე მაგიდები, შეკვეთები, რეზერვაციები, გადახდები და მენეჯერის საქმიანობა ერთი ოფლაინზე ორიენტირებული სისტემიდან, რომელიც ყოველ ცვლას მიჰყვება.",
    facts: ["სართული პირველია", "ოფლაინ მზადაა", "GEL-ზე მორგებული"],
  },
  floor: {
    ...ka.floor,
    title: "სართულის გეგმა ერთხელ შექმენი. ყოველდღიური სერვისი მისგან მართე.",
    body: "მოაწყვე მაგიდები, ოთახის ობიექტები და სერვისის ზონები ერთ მკაფიო რედაქტორში. იგივე გეგმა ყოველი ცვლის სამუშაო სივრცე გახდება.",
  },
  product: {
    ...ka.product,
    body: "გაჰყევი ერთ რეალურ POS ცვლას ცოცხალი სართულის გეგმიდან აქტიურ ჩეკამდე, შეკვეთის რედაქტირებამდე, გადახდამდე და დღის დახურვამდე.",
    tour: [
      { label: "სართულის გეგმა", title: "ჩეკის გახსნამდე ოთახი დაინახე", body: "თავისუფალი და დაკავებული მაგიდები, ოთახის ობიექტები, სერვისის მაჩვენებლები და შემდეგი რეზერვაცია ერთ ხედში ჩანს." },
      { label: "აქტიური მაგიდა", title: "მოქმედებამდე მთელი ჩეკი ნახე", body: "რეზერვაციის დეტალები, შეკვეთის პოზიციები, სერვისი, ჯამები, ბეჭდვა და მაგიდის მოქმედებები ერთ შეკვეთას მიჰყვება." },
      { label: "შეკვეთის დამატება", title: "კონტექსტის დაკარგვის გარეშე შეცვალე შეკვეთა", body: "ქართული კატეგორიები, მენიუს ფასები, რაოდენობები, სერვისი და ჯამი ერთ სამუშაო ხედში რჩება." },
      { label: "გადახდა", title: "გადახდის გზა მკაფიოდ აირჩიე", body: "ნაღდი, Bank POS და გაყოფილი გადახდა იმავე ჩეკზე ჩანს, რომ ოფიციანტმა შეკვეთა თავდაჯერებით დახუროს." },
      { label: "დღის დახურვა", title: "დახურვამდე იცოდე, რა გაჩერებს", body: "შემოსავალი, Z რეპორტი, ღია მაგიდები და რეზერვაციის ბლოკერები სამუშაო თარიღის შეცვლამდე ჩანს." },
    ],
  },
  reservations: {
    ...ka.reservations,
    title: "ონლაინ რეზერვაციები რესტორნის სამუშაო პროცესის ნაწილი ხდება.",
    body: "სტუმარი ონლაინ ჯავშნის, საჭიროების შემთხვევაში წინასწარ შეკვეთას ამატებს, გუნდი კი რეზერვაციას Vynic-ში მართავს.",
  },
  manager: {
    ...ka.manager,
    body: "თანამშრომლების როლები, დღის დახურვა, რეზერვაციები და დაცული მოქმედებები ერთი რესტორნის მდგომარეობის ნაწილია.",
    closeBody: "Vynic ღია მაგიდებზე გაფრთხილებს, სანამ დღის დახურვა სამუშაო თარიღს შეცვლის.",
  },
  local: {
    ...ka.local,
    title: "ქართული რესტორნების მუშაობაზე მორგებული.",
    body: "Vynic ითვალისწინებს ადგილობრივ სართულს, გადახდებს, ენას, სერვისის საფასურს, ბანკეტსა და დღის დახურვის პროცესს.",
  },
  form: {
    ...ka.form,
    title: "ნახე, როგორ მუშაობს Vynic შენს რესტორანში.",
    body: "მოგვიყევი შენს რესტორანზე და დემოს მაგიდებს, რეზერვაციებს, გადახდებსა და დღის დახურვას მოვარგებთ.",
    note: "დემოს შენს სართულს, რეზერვაციებსა და დღის დახურვის რიტმს მოვარგებთ.",
  },
  editor: {
    ...ka.editor,
    undo: "გაუქმება",
    snap: "ბადეზე მიბმა",
    place: "დასამატებლად დააჭირე",
    editName: "სახელი მარჯვენა პანელში შეცვალე",
    dragHelp: "გადაადგილება · Shift-დაჭერა რამდენიმე ობიექტის ასარჩევად · Delete წასაშლელად",
    canvas: "სამუშაო არე",
    canvasRatio: "სამუშაო სივრცის თანაფარდობა",
    objectsSelected: "არჩეული ობიექტი",
    clickFloor: "სამუშაო არეზე ნებისმიერ ადგილას დააჭირე",
  },
  screen: {
    ...ka.screen,
    count: "შეკვეთები",
    serviceNow: "მიმდინარე სერვისი",
    reservationContext: "რეზერვაციის დეტალები",
    guestFlow: "სტუმრის პროცესი",
    unfinishedTakeaway: "დაუსრულებელი გატანის შეკვეთა",
    walkIn: "ჯავშნის გარეშე",
  },
};

const nativeKa: SiteCopy = {
  ...polishedKa,
  nav: {
    ...polishedKa.nav,
    reservations: "ჯავშნები",
    manager: "მენეჯერის აპლიკაცია",
  },
  hero: {
    ...polishedKa.hero,
    eyebrow: "რესტორნის ოპერაციების POS სისტემა",
    title: "რესტორნის POS — დარბაზის მართვა",
    body: "მართე მაგიდები, შეკვეთები, ჯავშნები და გადახდები — მენეჯერისთვის საჭირო სურათი კი ერთ ოფლაინზე გათვლილ სისტემაში გქონდეს. Vynic ცვლას ბოლომდე მიჰყვება.",
    facts: ["დარბაზი პირველ ადგილზე", "ოფლაინ მუშაობა", "GEL-ზე მორგებული"],
  },
  capabilities: [
    { number: "01", label: "ოფლაინ რეჟიმი", body: "ინტერნეტის გათიშვის შემთხვევაშიც გააგრძელე შეკვეთების მიღება. კავშირის აღდგენისას ცვლილებები ავტომატურად დასინქრონდება." },
    { number: "02", label: "სამუშაო დღის დახურვა", body: "დახურე სამუშაო დღე ღია მაგიდების შემოწმებით, Z-რეპორტითა და დღის შემაჯამებელი GEL-ჯამებით." },
    { number: "03", label: "დარბაზის ვიზუალური გეგმა", body: "იმუშავე რეალური მაგიდების, გაერთიანებული მაგიდების, ჯავშნებისა და მიმდინარე სტატუსების მიხედვით." },
    { number: "04", label: "ჯავშნების მართვა", body: "სტუმრის მონაცემები, მაგიდის არჩევანი და შენიშვნები პერსონალისთვის ერთ სივრცეში შეინახე." },
    { number: "05", label: "მენეჯერის მობილური აპი", body: "მფლობელს მაგიდების, ჯავშნებისა და დღის შედეგების სწრაფი, ცოცხალი ხედვა ჰქონდეს." },
    { number: "06", label: "მოქმედებების ჟურნალი", body: "გაუქმება, დღის დახურვა და თანამშრომლებისა თუ მენეჯერის მოქმედებები ჩანაწერში დარჩეს." },
    { number: "07", label: "ქართული ინტერფეისი", body: "დარბაზის გუნდმა POS და მენეჯერის ეკრანები ქართულად გამოიყენოს." },
  ],
  floor: {
    ...polishedKa.floor,
    title: "სართულის გეგმა ერთხელ შექმენი — ყოველდღიური სერვისი კი მის მიხედვით მართე.",
    body: "განალაგე მაგიდები, დარბაზის ობიექტები და სერვისის ზონები ერთ მარტივ რედაქტორში. იგივე გეგმა ყოველი ცვლის სამუშაო სივრცე გახდება.",
  },
  product: {
    ...polishedKa.product,
    eyebrow: "პროდუქტის შესაძლებლობები",
    title: "ერთი სისტემა — პირველი მაგიდიდან დღის დახურვამდე.",
    body: "იხილე POS-ის სრული ცვლა: დარბაზის ცოცხალი გეგმა, გახსნილი ჩეკი, შეკვეთის რედაქტირება, გადახდა და დღის დახურვა.",
    shiftFlow: "ცვლის ეტაპები",
    tour: [
      { label: "დარბაზის გეგმა", title: "ჩეკის გახსნამდე მთელი დარბაზი დაინახე", body: "თავისუფალი და დაკავებული მაგიდები, დარბაზის ობიექტები, სერვისის მაჩვენებლები და შემდეგი ჯავშანი ერთ ხედში გაქვს." },
      { label: "აქტიური მაგიდა", title: "მოქმედებამდე სრული ჩეკი ნახე", body: "ჯავშნის დეტალები, შეკვეთის პოზიციები, მომსახურების საფასური, ჯამი, ბეჭდვა და მაგიდის მოქმედებები ერთ შეკვეთას მიჰყვება." },
      { label: "შეკვეთის მიღება", title: "შეკვეთა კონტექსტის დაკარგვის გარეშე შეცვალე", body: "ქართული კატეგორიები, ფასები, რაოდენობები, მომსახურების საფასური და მიმდინარე ჯამი ერთ ეკრანზე რჩება." },
      { label: "გადახდა", title: "გადახდის მეთოდი მკაფიოდ აირჩიე", body: "ნაღდი, საბანკო ტერმინალი და გაყოფილი გადახდა იმავე ჩეკზე ჩანს — მიმტანი შეკვეთას თავდაჯერებით ხურავს." },
      { label: "დღის დახურვა", title: "დახურვამდე იცოდე, რა გიშლის ხელს", body: "შემოსავალი, Z-რეპორტი, ღია მაგიდები, დაუმთავრებელი გატანის შეკვეთები და ჯავშნის ბლოკერები თარიღის შეცვლამდე ჩანს." },
    ],
  },
  reservations: {
    ...polishedKa.reservations,
    title: "ონლაინ ჯავშანი რესტორნის სამუშაო პროცესში პირდაპირ ერთვება.",
    body: "სტუმარი ონლაინ ჯავშნის, საჭიროების შემთხვევაში წინასწარ შეკვეთასაც ამატებს, გუნდი კი ყველაფერს Vynic-ში მართავს.",
    steps: [
      { title: "სტუმარი მაგიდას ირჩევს", body: "ჯავშანი ვებსაიტზე თარიღის, დროისა და მაგიდის არჩევით იწყება." },
      { title: "წინასწარი შეკვეთა ემატება", body: "ბანკეტისა და ღონისძიების ჯავშანს, საჭიროების შემთხვევაში, არჩეული კერძების ინფორმაცია მიჰყვება." },
      { title: "გუნდი Vynic-ში აგრძელებს მუშაობას", body: "სტუმრის მონაცემები, მაგიდის დეტალები და წინასწარი შეკვეთის შენიშვნები POS-ში ხვდება." },
    ],
  },
  manager: {
    ...polishedKa.manager,
    title: "მენეჯერი POS-ის რეალურ სურათს ხედავს.",
    body: "თანამშრომლების როლები, დღის დახურვა, ჯავშნები და მენეჯერის მიერ დაცული მოქმედებები ერთი სისტემის ნაწილია.",
    roleTitle: "წვდომების მართვა",
    roleBody: "მენეჯერები, სუპერვაიზერები, მიმტანები და PIN-კოდები მენეჯერის ცენტრშია თავმოყრილი.",
    closeTitle: "დღის დახურვის კონტროლი",
    closeBody: "დღის დახურვამდე Vynic გაჩვენებს ღია მაგიდებს და სხვა საკითხებს, რომლებიც ყურადღებას ითხოვს.",
    practicalTitle: "ყველაფერი საჭირო ერთ ხედში",
    points: ["თანამშრომლების როლები და PIN-კოდები", "დღის დახურვის გაფრთხილებები", "ჯავშნები", "შეკვეთები და ჯამები", "დაცული მენეჯერული მოქმედებები"],
  },
  local: {
    ...polishedKa.local,
    title: "ქართული რესტორნების მუშაობაზე მორგებული.",
    body: "Vynic შექმნილია იმ რეალური პროცესებისთვის, რომლებსაც ადგილობრივი რესტორნები ყოველდღე მართავენ: დარბაზი, გადახდები, ენა, მომსახურების საფასური, ბანკეტი და დღის დახურვა.",
    items: [
      { title: "ქართული ინტერფეისი", body: "დარბაზის გუნდს შეუძლია სამუშაო ენა ქართულად გამოიყენოს." },
      { title: "GEL და მომსახურების საფასური", body: "ჯამები, მომსახურების საფასური და ქართული გადახდის ჩვევები სამუშაო პროცესში მკაფიოდ ჩანს." },
      { title: "ადგილობრივი გადახდის მეთოდები", body: "ნაღდი თანხა, საბანკო ტერმინალი, GEL-ით დათვლილი ჯამები და მომსახურების საფასური ერთ ხედში რჩება." },
      { title: "ბანკეტი და ღონისძიების მაგიდები", body: "გაერთიანებული მაგიდები, წინასწარი შეკვეთა და ღონისძიების სერვისი სართულის გეგმას მიჰყვება." },
      { title: "გვიანი სერვისის შემდეგ დახურვა", body: "ღია მაგიდები, Z-რეპორტი, შემოსავალი და სამუშაო თარიღი დღის დახურვამდე ერთად ჩანს." },
    ],
  },
  form: {
    ...polishedKa.form,
    title: "ნახე, როგორ იმუშავებს Vynic შენს რესტორანში.",
    body: "მოგვიყევი შენს რესტორანზე და დემოს მაგიდების მართვის, ჯავშნების, გადახდებისა და დღის დახურვის პროცესს მოვარგებთ.",
    steps: [
      { number: "01", title: "შენი დარბაზი", body: "სართულის გეგმა, მაგიდების მიმდინარე მდგომარეობა და დიდი ჯგუფები." },
      { number: "02", title: "შენი ცვლა", body: "შეკვეთები, გადახდები, ჯავშნები და დღის დახურვა." },
      { number: "03", title: "შენი დღის დახურვა", body: "სამუშაო დღის შემოწმებები, ჯამები და მენეჯერის ხედვა." },
    ],
    restaurant: "რესტორნის სახელი",
    placeholder: "მოგვიყევი სართულის, ჯავშნებისა და გადახდების შესახებ.",
    requiredError: "სახელი, რესტორნის სახელი და ტელეფონის ნომერი აუცილებელია.",
    success: "დემოს მოთხოვნა მიღებულია. დემოს შენი გუნდის მუშაობას მოვარგებთ.",
    note: "დემოს შენს სართულს, ჯავშნებსა და დღის დახურვის რიტმს მოვარგებთ.",
  },
  editor: {
    ...polishedKa.editor,
    redo: "აღდგენა",
    preview: "წინასწარი ნახვა",
    rectangle: "მართკუთხა",
    square: "კვადრატული",
    structure: "კონსტრუქცია",
    annotation: "მონიშვნა",
    available: "თავისუფალია",
    selected: "არჩეულია",
    canvas: "სამუშაო არე",
    gridStep: "ბადის ზომა",
    editRoomBody: "მარცხნივ აირჩიე ობიექტი, შემდეგ სამუშაო არეზე დააჭირე მის დასამატებლად. ოთახის დასახვეწად ობიექტები გადაადგილე.",
    alignHelp: "არჩეული ობიექტები ხელსაწყოთა ზოლიდან გაასწორე ან კლავიატურით ერთად გადაადგილე.",
    transform: "გარდაქმნა",
    chooseTable: "პირველი მაგიდის დასამატებლად აირჩიე „მაგიდა“",
    clickFloor: "დასამატებლად სამუშაო არეზე ნებისმიერ ადგილას დააჭირე",
  },
  screen: {
    ...polishedKa.screen,
    takeaways: "გატანის შეკვეთები",
    free: "თავისუფალია",
    occupied: "დაკავებულია",
    reserved: "დაჯავშნილია",
    online: "ონლაინ",
    opened: "გახსნილია",
    forTable: "ამ მაგიდისთვის",
    confirmed: "დადასტურებულია",
    service: "მომსახურება",
    orderEditor: "შეკვეთის რედაქტორი",
    searchMenu: "მენიუში ძიება",
    grill: "გრილზე მომზადებული",
    availablePreorder: "წინასწარი შეკვეთისთვის ხელმისაწვდომია",
    managerCenter: "მენეჯერის ცენტრი",
    gelToday: "დღეს, GEL",
    guestFlow: "სტუმრის გზა",
    floorClose: "დარბაზი + დახურვა",
    posFloor: "POS-ის დარბაზი",
    sales: "სრული გაყიდვები",
    cash: "ნაღდი თანხა",
    bankPos: "საბანკო ტერმინალი",
    zReport: "Z-რეპორტი",
    zReportReady: "Z-რეპორტი მზად არის",
    noPrinterErrors: "პრინტერის შეცდომები არ დაფიქსირებულა",
    unfinishedTakeaway: "დაუსრულებელი გატანის შეკვეთა",
  },
};

const copies = { en, ka: nativeKa };

export function getCopy(locale: Locale): SiteCopy {
  return copies[locale];
}

export function localeFromPath(pathname = window.location.pathname): Locale {
  return pathname === "/ka" || pathname.startsWith("/ka/") ? "ka" : "en";
}

export function preferredLocale(): Locale {
  if (typeof window === "undefined") return "en";
  const saved = window.localStorage.getItem(LOCALE_STORAGE_KEY);
  return saved === "ka" ? "ka" : "en";
}

export function localeHref(locale: Locale) {
  return locale === "ka" ? "/ka" : "/en";
}

const LocaleContext = createContext<{ locale: Locale; copy: SiteCopy }>({ locale: "en", copy: en });

export function LocaleProvider({ children }: { children: ReactNode }) {
  const { pathname } = useLocation();
  const locale = localeFromPath(pathname);
  const value = useMemo(() => ({ locale, copy: getCopy(locale) }), [locale]);

  useEffect(() => {
    document.documentElement.lang = locale === "ka" ? "ka" : "en";
    document.title = locale === "ka" ? "Vynic | რესტორნის POS" : "Vynic | Restaurant POS";
    window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  }, [locale]);

  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}

export function useLocale() {
  return useContext(LocaleContext);
}
