export type PlatformRole = "SUPER_ADMIN";
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
  id: string;
  key: string;
  name: string;
  status: string;
  features: Array<{ feature: Pick<Feature, "key" | "name"> }>;
}

export interface ProductState {
  venueId: string;
  plan: Pick<Plan, "id" | "key" | "name" | "status"> | null;
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
  configuredMode: WebsiteMode;
  effectiveMode: WebsiteMode;
  entitled: boolean;
  consistent: boolean;
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
  actor: { id: string; email: string; displayName: string };
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
