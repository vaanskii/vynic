export type PlatformRole = "SUPER_ADMIN" | "SUPPORT_READONLY";
export type VenueStatus = "ACTIVE" | "DISABLED";
export type DeviceStatus = "ACTIVE" | "DISABLED" | "REVOKED";
export type DomainStatus = "ACTIVE" | "DISABLED";
export type WebsiteMode = "NONE" | "SAAS" | "CUSTOM";
export type OverrideEffect = "ENABLED" | "DISABLED";

export interface PlatformActor {
  platformUserId: string;
  email: string;
  displayName: string;
  role: PlatformRole;
}

export interface LoginResult {
  access_token: string;
  expiresIn: number;
  actor: PlatformActor;
}

export interface Page<T> {
  total: number;
  limit: number;
  offset: number;
  items: T[];
}

export interface Organization {
  id: string;
  name: string;
  createdAt: string;
  updatedAt: string;
  _count?: { venues: number };
  venues?: Venue[];
}

export interface Venue {
  loginCode: string;
  id: string;
  organizationId: string;
  name: string;
  status: VenueStatus;
  timezone: string;
  currency: string;
  createdAt: string;
  updatedAt: string;
  organization?: { id: string; name: string };
}

export interface Feature {
  id: string;
  key: string;
  name: string;
}

export interface Plan {
  description?: string | null;
  priceMinor?: number;
  currency?: string;
  billingPeriod?: string;
  mediaQuotaBytes?: number;
  mediaQuotaFiles?: number;
  id: string;
  key: string;
  name: string;
  status: string;
  features: Array<{ feature: Pick<Feature, "key" | "name"> }>;
}

export interface ProductState {
  commercialStatus?: string | null;
  menuManagement?: {
    authority: "POS" | "CLOUD";
    canEnableCloud: boolean;
    enabled: boolean;
    reason: string | null;
    /** Whether the package includes POS; menu authority follows it. */
    posIncluded?: boolean;
    /** Website without POS still on POS authority: nobody can edit the menu. */
    needsCloudAuthority?: boolean;
  };
  commercialAccess?: boolean;
  venueId: string;
  plan: Pick<Plan, "id" | "key" | "name" | "status"> | null;
  agreedPrice?: {
    priceMinor: number | null;
    currency: string | null;
    billingPeriod: string | null;
  } | null;
  planFeatures?: string[];
  planAssignedAt: string | null;
  overrides: Array<{
    featureKey: string;
    featureName: string;
    effect: OverrideEffect;
    note: string | null;
    updatedAt: string;
  }>;
  effectiveFeatures: string[];
  website: WebsiteAccess;
}

export interface WebsiteAccess {
  provisioning?: {
    status: string;
    assignedSlug: string | null;
    publishedAt: string | null;
  } | null;
  configuredMode: WebsiteMode;
  effectiveMode: WebsiteMode;
  entitled: boolean;
  consistent: boolean;
}

export type CustomWebsiteStatus =
  | "NOT_CONFIGURED"
  | "SETUP_PENDING"
  | "READY"
  | "ACTIVE"
  | "ERROR";

/** The operator's CUSTOM website view: binding, checklist and history. */
export interface CustomWebsite {
  venueId: string;
  mode: WebsiteMode;
  effectiveMode: WebsiteMode;
  entitled: boolean;
  commercialStatus: string;
  trialEndsAt: string | null;
  status: CustomWebsiteStatus;
  siteKey: string | null;
  statusNote: string | null;
  updatedAt: string | null;
  domains: Array<Pick<VenueDomain, "id" | "hostname" | "status" | "createdAt">>;
  /** Earliest ACTIVE public domain, else the earliest ACTIVE .localhost one. */
  primaryDomain: string | null;
  /** `https://<primary>/`; null when the Venue has no public domain. */
  publicUrl: string | null;
  /** Development only; the server omits it in production. */
  localFrontend?: CustomWebsiteLocalFrontend;
  menu: {
    authority: "POS" | "CLOUD";
    editingEnabled: boolean;
    posIncluded: boolean;
    needsCloudAuthority: boolean;
  };
  payments: "NOT_INCLUDED" | "NOT_CONFIGURED" | "DISABLED" | "ENABLED";
  readiness: {
    complete: boolean;
    checks: Record<"entitled" | "customMode" | "siteKey" | "activeDomain", boolean>;
  };
  audit: Array<{
    id: string;
    action: string;
    metadata: Record<string, unknown> | null;
    createdAt: string;
    actor: string;
  }>;
}

export type WebsiteCapabilityKey =
  | "MENU"
  | "HOURS"
  | "RESERVATIONS"
  | "GALLERY"
  | "CUSTOMER_ACCOUNTS"
  | "ONLINE_PAYMENTS"
  | "EVENTS"
  | "BANQUETS"
  | "ONLINE_ORDERING";

/** One shared website capability of a Venue; identical for SAAS and CUSTOM. */
export interface WebsiteCapability {
  key: WebsiteCapabilityKey;
  label: string;
  built: boolean;
  commercial: boolean;
  enabled: boolean;
  canEnable: boolean;
  ready: boolean;
  readyDetail: string | null;
  available: boolean;
  live: boolean;
  /** null: decided by the custom frontend build. */
  usedByFrontend: boolean | null;
}

/** Where this Venue's frontend dev server runs, from backend configuration. */
export interface CustomWebsiteLocalFrontend {
  state: "CONFIGURED" | "NO_SITE_KEY" | "NO_LOCAL_DOMAIN" | "NOT_CONFIGURED";
  siteKey: string | null;
  hostname: string | null;
  port: number | null;
  url: string | null;
  source: string;
  detail: string;
  problems: string[];
}

/** An on-demand reachability answer; never stored, never a setup status. */
export interface CustomWebsiteCheck {
  availability: "REACHABLE" | "UNREACHABLE";
  checkedAt: string;
  hostname: string;
  url: string;
  frontend: { status: number | null; detail: string };
  api: {
    state: "OK" | "WRONG_SITE" | "FAILED" | "NOT_CHECKED";
    status: number | null;
    detail: string;
  };
}

export interface VenueDomain {
  id: string;
  venueId: string;
  hostname: string;
  status: DomainStatus;
  createdAt: string;
  updatedAt: string;
}

export interface Device {
  isOperationalPrimary: boolean;
  activeOperationalDeviceId: string | null;
  id: string;
  venueId: string;
  installationId: string;
  displayName: string;
  platform: string;
  status: DeviceStatus;
  lastSeenAt: string | null;
  createdAt: string;
  updatedAt: string;
}

/**
 * What happened to one invitation. Derived on the backend from its timestamps,
 * so there is no second answer here to drift from — and deliberately not an
 * online/offline state, which nothing can honestly report.
 */
export type EnrollmentStatus = "PENDING" | "ENROLLED" | "EXPIRED" | "CANCELLED";

export interface DeviceEnrollment {
  id: string;
  venueId: string;
  /** Half a code. Safe to show; it cannot enroll anything on its own. */
  codeSelector: string;
  displayName: string;
  platform: string;
  expiresAt: string;
  attemptCount: number;
  redeemedAt: string | null;
  redeemedInstallationId: string | null;
  deviceId: string | null;
  cancelledAt: string | null;
  createdAt: string;
  updatedAt: string;
  status: EnrollmentStatus;
}

export interface IssuedEnrollment {
  id: string;
  venueId: string;
  displayName: string;
  platform: string;
  expiresAt: string;
  status: EnrollmentStatus;
  /** Shown once. Only a verifier is stored, so it cannot be read back. */
  code: string;
}

export interface IssuedCredential {
  device: Pick<Device, "id" | "venueId" | "installationId">;
  credential: string;
}

export interface AuditEvent {
  id: string;
  action: string;
  targetType: string;
  targetId: string;
  metadata: Record<string, unknown> | null;
  createdAt: string;
  actor: { id: string; email: string; displayName: string } | null;
}

export interface QueuedCommand {
  commandId: string;
  status: string;
  idempotencyKey: string;
}

export interface EdgeCommandStatus {
  commandId: string;
  type: string;
  status: "PENDING" | "CLAIMED" | "SUCCEEDED" | "FAILED";
  attemptCount: number;
  maxAttempts: number;
  claimedAt: string | null;
  acknowledgedAt: string | null;
  resultCode: string | null;
  resultDetail: string | null;
  createdAt: string;
  updatedAt: string;
  claimedBy: { id: string; displayName: string } | null;
  device: { id: string; displayName: string } | null;
}

export type SubscriptionStatus =
  | "NO_PLAN"
  | "TRIAL"
  | "ACTIVE"
  | "PAST_DUE"
  | "SUSPENDED"
  | "CANCELLED";
export interface VenueSubscription {
  status: SubscriptionStatus;
  startedAt: string | null;
  trialEndsAt: string | null;
  currentPeriodEndsAt: string | null;
  note: string | null;
}
export interface ManagerAccess {
  delivery?: { id: string; status: string; resultCode: string | null } | null;
  id: string;
  username: string;
  displayName: string | null;
  role: "MANAGER" | "ADMIN";
  isActive: boolean;
}
export interface PlatformUserRow {
  id: string;
  email: string;
  displayName: string;
  role: PlatformRole;
  status: "ACTIVE" | "DISABLED";
}
