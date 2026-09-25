/**
 * Wire types of the shared Vynic public website API, as a CUSTOM frontend
 * receives them. The Venue is always the one the request Host resolved to;
 * none of these types carries a Venue id the client could choose.
 */

export type Localized = { ka: string; en: string };

/** Operator-tracked setup of a CUSTOM site. */
export type CustomSiteStatus =
  | "NOT_CONFIGURED"
  | "SETUP_PENDING"
  | "READY"
  | "ACTIVE"
  | "ERROR";

/**
 * What the backend switches on for this Venue. Derived from the Venue's
 * commercial features and configured data; a frontend hides what is false.
 */
export type SiteCapabilities = {
  profile: boolean;
  menu: boolean;
  customerAccounts: boolean;
  onlinePayments: boolean;
  reservations: boolean;
};

export type VenueProfile = {
  name: string;
  branchName: string | null;
  address: string | null;
  phone: string | null;
  timezone: string;
  currency: string;
};

/** `GET /api/website/custom/bootstrap` */
export type CustomSiteBootstrap = {
  schemaVersion: 1;
  mode: "CUSTOM";
  site: { key: string | null; status: CustomSiteStatus };
  profile: VenueProfile;
  capabilities: SiteCapabilities;
};

export type MenuVariant = { id: string; size: number; price: number };

export type MenuItem = {
  id: string;
  name: Localized;
  /** Owner-chosen public name; falls back to `name` when null. */
  displayName: string | null;
  description: string | null;
  imageUrl: string | null;
  price: number;
  variants: MenuVariant[];
};

export type MenuCategory = {
  id: string;
  slug: string;
  name: Localized;
  items: MenuItem[];
  subcategories: Array<{
    id: string;
    slug: string;
    name: Localized;
    items: MenuItem[];
  }>;
};

/** `GET /api/website/custom/menu`: hidden and disabled items never appear. */
export type CustomSiteMenu = {
  schemaVersion: 1;
  currency: string;
  categories: MenuCategory[];
};

export type WebsiteTable = {
  id: number;
  tableNumber: string;
  capacity: number;
  posFloor: string;
};

export type TableAvailability = {
  id: number;
  tableNumber: string;
  capacity: number;
  posFloor: string;
  isAvailable: boolean;
  bookedTimeSlots: string[];
  date: string;
};

/**
 * A paid booking request. Prices are recomputed by the server from the
 * Venue's own menu; the account comes from the session cookie, never from
 * this body.
 */
export type BookingRequest = {
  selectedTables: string[];
  selectedDate: string;
  selectedTime: string;
  menuItems?: Array<{ id: string; quantity: number }>;
  customerName?: string;
  customerEmail?: string;
  customerPhone?: string;
  notes?: string;
  numberOfGuests?: number;
  language?: "ka" | "en" | "ru";
};

export type BookingResult = {
  success: boolean;
  /** Bank checkout page; redirect the browser here. */
  redirect_url?: string;
  reservation_id: string;
};

export type PaymentStatus = {
  success: boolean;
  status?: "CONFIRMED" | "FAILED" | "PENDING";
  message?: string;
};

export type WebsiteSession =
  | { isAuthenticated: false }
  | {
      isAuthenticated: true;
      user: {
        id: string;
        phone: string;
        firstName?: string | null;
        lastName?: string | null;
        email?: string | null;
      };
    };
