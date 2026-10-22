import { Navigate, useLocation } from "react-router-dom";

/**
 * The owner dashboard lives under /dashboard, one path per section, so a
 * refresh, a shared link or the back button lands on the same place.
 */
export const dashboardSections = [
  ["home", "მთავარი"],
  ["restaurant", "რესტორნის პროფილი"],
  ["website", "ვებსაიტი"],
  ["menu", "მენიუ"],
  ["photos", "ფოტოები"],
  ["hours", "სამუშაო საათები"],
  ["payments", "ონლაინ გადახდები"],
  ["devices", "მოწყობილობები / POS"],
  ["managers", "მენეჯერები"],
  ["subscription", "გამოწერა"],
  ["settings", "პარამეტრები"],
] as const;
export type DashboardSection = (typeof dashboardSections)[number][0];

export const isDashboardSection = (value?: string): value is DashboardSection =>
  dashboardSections.some(([key]) => key === value);

export const dashboardPath = (section: DashboardSection) =>
  section === "home" ? "/dashboard" : `/dashboard/${section}`;

/** Section names the old portal used in `?section=`. */
const legacySections: Record<string, DashboardSection> = { profile: "restaurant" };

/**
 * Old /portal links keep working. The owner area used to live at /portal
 * with `?section=`, sign-in on the same page, and invitations at
 * /portal/invite; the invitation token travels in the fragment, so the
 * fragment is carried over untouched.
 */
export function PortalRedirect() {
  const { pathname, search, hash } = useLocation();
  const rest = pathname.replace(/^\/portal\/?/, "").replace(/\/$/, "");
  const params = new URLSearchParams(search);
  const requested = params.get("section") ?? "";
  params.delete("section");
  const query = params.toString() ? `?${params}` : "";

  let to: string;
  if (rest === "signup") to = "/request-access";
  else if (rest === "login") to = "/login";
  else if (rest === "invite" || rest.startsWith("invite/")) to = `/${rest}`;
  else {
    const section = legacySections[rest || requested] ?? (rest || requested);
    to = isDashboardSection(section) ? dashboardPath(section) : "/dashboard";
  }
  return <Navigate to={`${to}${query}${hash}`} replace />;
}
