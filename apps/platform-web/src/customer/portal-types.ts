/** Shapes returned by `GET /customer/portal` (see CustomerService.status). */
export type PrinterSettings = { host: string; port: number; enabled: boolean };
export type RuntimeConfig = {
  printers?: { kitchen: PrinterSettings; receipt: PrinterSettings };
} | null;
export type Device = {
  id: string;
  displayName: string;
  status: string;
  lastSeenAt: string | null;
  firstSyncAt?: string | null;
  runtimeConfig: RuntimeConfig;
  isOperationalPrimary: boolean;
};
export type Enrollment = { id: string; status: string; codeSelector: string };
export type IssuedEnrollment = { id: string; code: string; expiresAt: string };
export type Manager = {
  id: string;
  displayName?: string | null;
  username: string;
  isActive: boolean;
};
export type VenueStatus = {
  venue: {
    id: string;
    name: string;
    branchName?: string | null;
    address?: string | null;
    phone?: string | null;
    legalId?: string | null;
    loginCode: string;
    timezone?: string;
    currency?: string;
    activeOperationalDeviceId?: string | null;
  };
  organization?: { name: string };
  plan?: { name: string } | null;
  subscription?: { status: string; trialEndsAt?: string | null } | null;
  features: string[];
  managers: Manager[];
  devices: Device[];
  enrollments: Enrollment[];
  checklist: Record<string, boolean>;
  ready: boolean;
};
export type Portal = {
  account: {
    email: string;
    displayName?: string;
    emailVerifiedAt?: string | null;
  };
  releaseLinks: Record<string, string>;
  websiteBaseDomain?: string | null;
  venues: VenueStatus[];
};
