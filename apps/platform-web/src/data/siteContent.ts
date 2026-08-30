import {
  PencilRuler,
  Printer,
} from "@phosphor-icons/react";
import screenFloorEditor from "../assets/screen-floor-editor.png";
import screenRestaurantSettings from "../assets/screen-restaurant-settings.png";
import managerAndroidDashboard from "../assets/manager-android-dashboard.png";
import posLiveDayClose from "../assets/pos-live-day-close.jpg";
import posLiveFloor from "../assets/pos-live-floor.jpg";
import posLiveOrderEditor from "../assets/pos-live-order-editor.jpg";
import posLivePayment from "../assets/pos-live-payment.jpg";
import posLiveReservation from "../assets/pos-live-reservation.jpg";
import posLiveTableOrder from "../assets/pos-live-table-order.jpg";
import { getCopy, type Locale } from "../lib/i18n";

export type ScreenshotSpec = {
  filename: string;
  dimensions: string;
  capture: string;
  alt: string;
  src?: string;
  aspect?: string;
  objectPosition?: string;
  facts?: string[];
  priority?: boolean;
  replica?: "floor" | "table-order" | "order-editor" | "payment" | "day-close";
};

export type Capability = {
  number: string;
  label: string;
  body: string;
};

export const navItems = [
  { label: "Product", href: "#product" },
  { label: "Floor Plan", href: "#floor-plan" },
  { label: "Reservations", href: "#reservations" },
  { label: "Manager App", href: "#manager" },
  { label: "Contact", href: "#contact" },
];

export const capabilities: Capability[] = [
  {
    number: "01",
    label: "Offline service",
    body: "Keep taking orders when the connection drops, then sync service state when it returns.",
  },
  {
    number: "02",
    label: "Business-day close",
    body: "Close the operating day with open-table checks, Z report context, and GEL totals.",
  },
  {
    number: "03",
    label: "Visual floor plan",
    body: "Run the room from actual tables, merged parties, reservations, and live status.",
  },
  {
    number: "04",
    label: "Reservation handling",
    body: "Keep guest details, table context, and reservation notes together for staff.",
  },
  {
    number: "05",
    label: "Manager mobile",
    body: "Give owners a smaller live view for tables, reservations, and day movement.",
  },
  {
    number: "06",
    label: "Audit trail",
    body: "Keep cancel, close, staff, and manager actions attached to the restaurant record.",
  },
  {
    number: "07",
    label: "Georgian interface",
    body: "Let the floor team work in Georgian across POS and manager screens.",
  },
];

export const screenshots: Record<string, ScreenshotSpec> = {
  floorEditor: {
    filename: "screen-floor-editor.png",
    dimensions: "3456 x 2234",
    capture: "Floor editor with grid, table shape controls, chair counts, ratios, and saved layout",
    alt: "Vynic floor editor showing table layout controls, a grid canvas, bar object, nine tables, and chair setup",
    src: screenFloorEditor,
    aspect: "3456 / 2234",
    facts: ["Layout mode", "Table spacing", "Seat setup"],
  },
  floorLive: {
    filename: "pos-live-floor.jpg",
    dimensions: "800 x 632",
    capture: "Active POS floor showing free, occupied, and reserved tables across the main hall",
    alt: "Live Vynic POS floor plan with Georgian labels, table status counts, bar, stage, and reservation panel",
    src: posLiveFloor,
    aspect: "800 / 632",
    facts: ["Live floor state", "Occupied + reserved", "Reservation context"],
    replica: "floor",
  },
  tableOrder: {
    filename: "pos-live-table-order.jpg",
    dimensions: "800 x 632",
    capture: "Active table order with reservation context, line items, service fee, and table actions",
    alt: "Live Vynic POS Table 1 order showing a 368 GEL subtotal, service fee, payable total, and table actions",
    src: posLiveTableOrder,
    aspect: "800 / 632",
    facts: ["23 items", "368.00 GEL subtotal", "404.80 GEL payable"],
    replica: "table-order",
  },
  orderEntry: {
    filename: "pos-live-order-editor.jpg",
    dimensions: "800 x 632",
    capture: "Live POS order editor with Georgian categories, search, quantity controls, and a running total",
    alt: "Live Vynic POS order editor with Georgian menu categories, GEL prices, quantities, and a 404.80 GEL total",
    src: posLiveOrderEditor,
    aspect: "800 / 632",
    facts: ["21 categories", "Items from 5 to 25 GEL", "Service enabled"],
    replica: "order-editor",
  },
  payment: {
    filename: "pos-live-payment.jpg",
    dimensions: "800 x 632",
    capture: "Live POS payment-method chooser over the active Table 1 order",
    alt: "Live Vynic POS payment chooser with cash, Bank POS, and split-payment methods",
    src: posLivePayment,
    aspect: "800 / 632",
    facts: ["Cash", "Bank POS", "Split payment"],
    replica: "payment",
  },
  posReservations: {
    filename: "pos-live-reservation.jpg",
    dimensions: "800 x 632",
    capture: "Live POS reservation editor with date, time, guest, phone, party size, and order context",
    alt: "Live Vynic POS reservation editor with date, time, Walk-in guest, phone, party size, and Order 1756 fields",
    src: posLiveReservation,
    aspect: "800 / 632",
    facts: ["Walk-in", "22/6/2026 at 23:56", "Order #1756"],
  },
  managerStaff: {
    filename: "screen-manager-staff.png",
    dimensions: "3456 x 2234",
    capture: "Manager center staff and role controls",
    alt: "Vynic manager center staff screen with four team members, role controls, and PIN management",
    facts: ["Staff roles", "Manager and waiter roles", "PIN control"],
  },
  closeDay: {
    filename: "pos-live-day-close.jpg",
    dimensions: "800 x 632",
    capture: "Manager center close-day workflow with business date, Z report, revenue, and open-table warning",
    alt: "Live Vynic POS day-close screen with seven closed orders, 2743.50 GEL revenue, three blockers, and Z report controls",
    src: posLiveDayClose,
    aspect: "800 / 632",
    facts: ["7 closed orders", "2743.50 GEL revenue", "3 close blockers"],
    replica: "day-close",
  },
  restaurantSettings: {
    filename: "screen-restaurant-settings.png",
    dimensions: "3456 x 2234",
    capture: "Restaurant settings with receipt logo, contact fields, service fee, and POS layout preferences",
    alt: "Vynic restaurant settings screen with logo, contact fields, receipt layout, and service fee configuration",
    src: screenRestaurantSettings,
    aspect: "3456 / 2234",
    facts: ["Receipt setup", "Service fee rules", "POS layout preferences"],
  },
  managerMobile: {
    filename: "screen-manager-mobile.png",
    dimensions: "1280 x 2856",
    capture: "Manager mobile dashboard with live tables, reservations, and day visibility",
    alt: "Vynic Manager mobile dashboard in Georgian with business-day status, live GEL totals, and navigation",
    src: managerAndroidDashboard,
    aspect: "1280 / 2856",
    objectPosition: "top center",
    facts: ["Active service day", "2,868.65 GEL movement", "Georgian manager view"],
  },
  websiteReservation: {
    filename: "screen-website-reservation.png",
    dimensions: "1600 x 1000",
    capture: "Guest website reservation flow with date, table, and time selection",
    alt: "Vynic website reservation flow with date, table, and time selection",
  },
  websitePreorder: {
    filename: "screen-website-preorder.png",
    dimensions: "1600 x 1000",
    capture: "Guest preorder step using the restaurant menu before confirmation",
    alt: "Vynic website preorder flow with menu items attached to a booking",
  },
};

export const floorPlanDetails = [
  {
    icon: PencilRuler,
    title: "Different table states stay visible",
    body: "Free, occupied, reserved, and merged tables all stay readable from the same floor view.",
  },
  {
    icon: Printer,
    title: "Bigger parties do not break the floor",
    body: "When staff merge Table 6 and Table 7, the floor changes with the service instead of hiding that work in a list.",
  },
];

export const serviceTour = [
  {
    label: "FLOOR PLAN",
    title: "Read the room before opening a check",
    body: "Free and occupied tables, floor objects, service counts, and the next reservation stay visible together.",
    screenshot: screenshots.floorLive,
  },
  {
    label: "ACTIVE TABLE",
    title: "See the whole check before acting",
    body: "Reservation context, line items, service, totals, print actions, and table controls remain attached to one order.",
    screenshot: screenshots.tableOrder,
  },
  {
    label: "ORDER ENTRY",
    title: "Edit the order without losing context",
    body: "Georgian categories, menu prices, quantities, service, and the running total stay in one working view.",
    screenshot: screenshots.orderEntry,
  },
  {
    label: "PAYMENT",
    title: "Choose the payment path clearly",
    body: "Cash, Bank POS, and split payment appear over the same check so the waiter can close with confidence.",
    screenshot: screenshots.payment,
  },
  {
    label: "DAY CLOSE",
    title: "Know what blocks close before pressing it",
    body: "Revenue, Z report, open tables, unfinished takeaways, and reservation blockers stay visible before the business date moves.",
    screenshot: screenshots.closeDay,
  },
];

export const reservationSteps = [
  {
    title: "Guest selects a table",
    body: "The booking flow starts with date, table, and time selection from the restaurant website.",
    screenshot: screenshots.websiteReservation,
  },
  {
    title: "Preorder can be attached",
    body: "Banquet or event-style reservations can carry selected menu context when that flow is used.",
    screenshot: screenshots.websitePreorder,
  },
  {
    title: "Staff manage it in Vynic",
    body: "Guest details, table context, and preorder notes reach the POS side for staff to review and manage.",
    screenshot: screenshots.posReservations,
  },
];

export const localFitItems = [
  {
    title: "Georgian interface",
    body: "The operating language can match the team on the floor.",
    tone: "plum",
  },
  {
    title: "GEL and service fee",
    body: "Totals, fee context, and Georgian restaurant payment habits stay visible in the workflow.",
    tone: "green",
  },
  {
    title: "Local payment context",
    body: "Cash, Bank POS, GEL totals, and service fee context stay visible in the workflow.",
    tone: "amber",
  },
  {
    title: "Banquet and event tables",
    body: "Merged tables, preorder context, and event-style service can stay tied to the floor.",
    tone: "charcoal",
  },
  {
    title: "Close-day after late service",
    body: "Open-table warnings, Z report, revenue, and the business date stay together before the day closes.",
    tone: "plum",
  },
];

export const managerPoints = [
  "Staff roles and PINs",
  "Close-day warnings",
  "Reservations",
  "Orders and totals",
  "Guarded manager actions",
];

export function getLocalizedContent(locale: Locale) {
  const content = getCopy(locale);
  return {
    navItems: [
      { label: content.nav.product, href: "#product" },
      { label: content.nav.floorPlan, href: "#floor-plan" },
      { label: content.nav.reservations, href: "#reservations" },
      { label: content.nav.manager, href: "#manager" },
      { label: content.nav.contact, href: "#contact" },
    ],
    capabilities: content.capabilities,
    serviceTour: content.product.tour.map((tourItem, index) => ({ ...tourItem, screenshot: serviceTour[index].screenshot })),
    reservationSteps: content.reservations.steps.map((step, index) => ({ ...step, screenshot: reservationSteps[index].screenshot })),
    localFitItems: content.local.items.map((item, index) => ({ ...item, tone: localFitItems[index].tone })),
    managerPoints: content.manager.points,
  };
}
