import type { WebsiteCapabilityKey, WebsiteMode } from '@prisma/client';

/**
 * Shared website capabilities: what one Venue's public website can offer,
 * whichever frontend renders it.
 *
 * Commercial entitlement (Features) -> Venue policy (operator switch, default
 * on) -> configuration (data the capability needs) -> what a frontend may
 * consume. WebsiteMode takes no part in any of those; it only answers which
 * capabilities the current *renderer* is known to display.
 */
export type WebsiteCapabilityName =
  | WebsiteCapabilityKey
  | 'EVENTS'
  | 'BANQUETS'
  | 'ONLINE_ORDERING';

interface CapabilityDefinition {
  key: WebsiteCapabilityName;
  label: string;
  /** False: no backend exists yet, so there is nothing to switch on. */
  built: boolean;
  /** Effective Features that must all be present. */
  features: readonly string[];
}

export const WEBSITE_CAPABILITIES: readonly CapabilityDefinition[] = [
  { key: 'MENU', label: 'Menu', built: true, features: ['WEBSITE'] },
  { key: 'HOURS', label: 'Hours', built: true, features: ['WEBSITE'] },
  {
    key: 'RESERVATIONS',
    label: 'Reservations',
    built: true,
    features: ['WEBSITE'],
  },
  { key: 'GALLERY', label: 'Gallery', built: true, features: ['WEBSITE'] },
  {
    key: 'CUSTOMER_ACCOUNTS',
    label: 'Customer accounts',
    built: true,
    features: ['WEBSITE'],
  },
  {
    key: 'ONLINE_PAYMENTS',
    label: 'Online payments',
    built: true,
    features: ['WEBSITE', 'ONLINE_PAYMENTS'],
  },
  { key: 'EVENTS', label: 'Events', built: false, features: [] },
  { key: 'BANQUETS', label: 'Banquets', built: false, features: [] },
  {
    key: 'ONLINE_ORDERING',
    label: 'Online ordering',
    built: false,
    features: [],
  },
];

/** The capabilities the generic SAAS renderer (`apps/restaurant-web`) shows. */
const SAAS_RENDERER: ReadonlySet<WebsiteCapabilityName> = new Set([
  'MENU',
  'HOURS',
  'GALLERY',
]);

export interface CapabilityFacts {
  features: readonly string[];
  /** Operator policy rows; a missing key means enabled. */
  policy: Partial<Record<WebsiteCapabilityKey, boolean>>;
  menuItems: number;
  hours: number;
  galleryPhotos: number;
  bookableTables: number;
  payment: { enabled: boolean } | null;
}

export interface CapabilityState {
  key: WebsiteCapabilityName;
  label: string;
  built: boolean;
  /** The package allows it (effective Features). */
  commercial: boolean;
  /** Operator policy for this Venue. Always false when not built. */
  enabled: boolean;
  /** Whether an operator may switch it on now (never an impossible switch). */
  canEnable: boolean;
  /** The data/configuration it needs exists. */
  ready: boolean;
  readyDetail: string | null;
  /** Commercial and enabled: owners may manage it and routes accept it. */
  available: boolean;
  /** Available and ready: what a frontend can actually use. */
  live: boolean;
  /** Whether the current renderer displays it; null when the custom build decides. */
  usedByFrontend: boolean | null;
}

function readiness(
  key: WebsiteCapabilityName,
  facts: CapabilityFacts,
  paymentsLive: boolean,
): [boolean, string | null] {
  switch (key) {
    case 'MENU':
      return facts.menuItems > 0 ? [true, null] : [false, 'No menu items yet'];
    case 'HOURS':
      return facts.hours > 0 ? [true, null] : [false, 'No opening hours yet'];
    case 'GALLERY':
      return facts.galleryPhotos > 0
        ? [true, null]
        : [false, 'No gallery photos yet'];
    case 'CUSTOMER_ACCOUNTS':
      return [true, null];
    case 'ONLINE_PAYMENTS':
      if (!facts.payment) return [false, 'Bank of Georgia is not configured'];
      return facts.payment.enabled
        ? [true, null]
        : [false, 'The payment integration is switched off'];
    case 'RESERVATIONS':
      if (facts.bookableTables === 0)
        return [false, 'No bookable website tables'];
      // The current booking flow takes a deposit through BOG.
      return paymentsLive
        ? [true, null]
        : [false, 'Bookings are paid online, and online payments are not live'];
    default:
      return [false, 'Not built'];
  }
}

export function websiteCapabilities(
  facts: CapabilityFacts,
  mode: WebsiteMode,
): CapabilityState[] {
  const base = (definition: CapabilityDefinition) => {
    const commercial =
      definition.built &&
      definition.features.every((f) => facts.features.includes(f));
    const enabled =
      definition.built &&
      facts.policy[definition.key as WebsiteCapabilityKey] !== false;
    return { commercial, enabled, available: commercial && enabled };
  };
  const payments = WEBSITE_CAPABILITIES.find(
    (d) => d.key === 'ONLINE_PAYMENTS',
  )!;
  const paymentsLive =
    base(payments).available && readiness(payments.key, facts, false)[0];
  return WEBSITE_CAPABILITIES.map((definition) => {
    const { commercial, enabled, available } = base(definition);
    const [ready, readyDetail] = definition.built
      ? readiness(definition.key, facts, paymentsLive)
      : [false, 'Not built'];
    return {
      key: definition.key,
      label: definition.label,
      built: definition.built,
      commercial,
      enabled,
      canEnable: commercial,
      ready,
      readyDetail,
      available,
      live: available && ready,
      usedByFrontend:
        mode === 'SAAS'
          ? SAAS_RENDERER.has(definition.key)
          : mode === 'CUSTOM'
            ? null
            : false,
    };
  });
}

/** The compact public answer a frontend branches on. */
export function publicCapabilities(states: readonly CapabilityState[]) {
  const live = (key: WebsiteCapabilityName) =>
    states.find((s) => s.key === key)?.live ?? false;
  return {
    profile: true,
    menu: live('MENU'),
    hours: live('HOURS'),
    gallery: live('GALLERY'),
    reservations: live('RESERVATIONS'),
    customerAccounts: live('CUSTOMER_ACCOUNTS'),
    onlinePayments: live('ONLINE_PAYMENTS'),
  };
}

export type PublicWebsiteCapabilities = ReturnType<typeof publicCapabilities>;

export function readCapabilityKey(value: unknown): WebsiteCapabilityKey | null {
  const found = WEBSITE_CAPABILITIES.find((d) => d.key === value && d.built);
  return found ? (found.key as WebsiteCapabilityKey) : null;
}
