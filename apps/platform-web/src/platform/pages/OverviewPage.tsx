import { Buildings, ChartDonut, SlidersHorizontal, Storefront, WarningCircle } from "@phosphor-icons/react";
import { useQueries, useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { platformApi } from "../api";
import { errorMessage, formatDateTime, formatRelativeTime, humanize } from "../format";
import { PageHeader, Panel } from "../components/Page";
import { ErrorState, LoadingState } from "../components/State";
import { StatusBadge } from "../components/StatusBadge";

export function OverviewPage() {
  const organizations = useQuery({ queryKey: ["organizations", 1, 0], queryFn: () => platformApi.organizations(1, 0) });
  const venues = useQuery({ queryKey: ["venues", { limit: 200, offset: 0 }], queryFn: () => platformApi.venues({ limit: 200 }) });
  const plans = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  const features = useQuery({ queryKey: ["features"], queryFn: platformApi.features });
  const audit = useQuery({ queryKey: ["audit", 8, 0], queryFn: () => platformApi.audit(8, 0) });
  const venueDetails = useQueries({ queries: (venues.data?.items ?? []).map((venue) => ({
    queryKey: ["overview-readiness", venue.id],
    queryFn: async () => {
      const [product, domains, devices] = await Promise.all([platformApi.product(venue.id), platformApi.domains(venue.id), platformApi.devices(venue.id)]);
      return { venue, product, domains, devices };
    },
  })) });

  const baseQueries = [organizations, venues, plans, features];
  if (baseQueries.some((query) => query.isPending) || venueDetails.some((query) => query.isPending)) return <LoadingState label="Loading platform overview" />;
  const failed = baseQueries.find((query) => query.error) ?? venueDetails.find((query) => query.error);
  if (failed) return <ErrorState error={errorMessage(failed.error)} retry={() => { baseQueries.forEach((query) => void query.refetch()); venueDetails.forEach((query) => void query.refetch()); }} />;

  const details = venueDetails.flatMap((query) => query.data ? [query.data] : []);
  const attention = details.flatMap(({ venue, product, domains, devices }) => {
    const items: Array<{ title: string; body: string; to: string; kind: "warning" | "danger" }> = [];
    if (!product.plan) items.push({ title: `${venue.name} has no plan`, body: "Assign a plan to establish inherited access.", to: `/admin/venues/${venue.id}/product`, kind: "warning" });
    if (!product.website.consistent) items.push({ title: `${venue.name} has a website inconsistency`, body: "Entitlement and configured mode need review.", to: `/admin/venues/${venue.id}/website`, kind: "warning" });
    if (product.website.entitled && product.website.effectiveMode !== "NONE" && domains.every((domain) => domain.status !== "ACTIVE")) items.push({ title: `${venue.name} has no active domain`, body: "The website is configured but has no active hostname.", to: `/admin/venues/${venue.id}/website`, kind: "warning" });
    if (devices.length === 0) items.push({ title: `${venue.name} has no devices`, body: "Add a POS device before handoff.", to: `/admin/venues/${venue.id}/devices`, kind: "danger" });
    const neverSeen = devices.filter((device) => !device.lastSeenAt).length;
    if (neverSeen) items.push({ title: `${venue.name}: ${neverSeen} device${neverSeen === 1 ? "" : "s"} never connected`, body: "Review provisioning and connection setup.", to: `/admin/venues/${venue.id}/devices`, kind: "danger" });
    const inactive = devices.filter((device) => device.status !== "ACTIVE").length;
    if (inactive) items.push({ title: `${venue.name}: ${inactive} device${inactive === 1 ? " is" : "s are"} disabled or revoked`, body: "Review lifecycle state before service depends on it.", to: `/admin/venues/${venue.id}/devices`, kind: "danger" });
    return items;
  });

  const metrics = [
    { label: "Organizations", value: organizations.data?.total ?? 0, note: "Tenant groups", icon: Buildings, to: "/admin/organizations" },
    { label: "Venues", value: venues.data?.total ?? 0, note: "Managed locations", icon: Storefront, to: "/admin/venues" },
    { label: "Plans", value: plans.data?.length ?? 0, note: "Commercial packages", icon: ChartDonut, to: "/admin/plans" },
    { label: "Features", value: features.data?.length ?? 0, note: "Platform capabilities", icon: SlidersHorizontal, to: "/admin/features" },
  ];

  return <>
    <PageHeader eyebrow="Platform overview" title="Good control starts with the real state." description="A current view of venue configuration, device readiness, and high-impact platform changes." />
    <div className="platform-grid platform-grid--metrics">{metrics.map(({ label, value, note, icon: Icon, to }) => <Link className="platform-metric" to={to} key={label}><div className="platform-metric__top"><span>{label}</span><Icon size={19} weight="duotone" /></div><strong>{value}</strong><p>{note}</p></Link>)}</div>
    <Panel title={attention.length ? `${attention.length} attention item${attention.length === 1 ? "" : "s"}` : "All venues are accounted for"} description={attention.length ? "Open an item to go straight to the venue action that resolves it." : "No missing plan, website, domain, or device setup was found in the loaded venue directory."} className="platform-overview-attention"><div className="platform-attention-list">{attention.length ? attention.map(({ title, body, to, kind }) => <Link to={to} className={`platform-attention platform-attention--${kind}`} key={title}><span className="platform-attention__icon"><WarningCircle size={18} weight="duotone" /></span><span><strong>{title}</strong><small>{body}</small></span><span className="platform-text-link">Open →</span></Link>) : <div className="platform-clear-state"><StatusBadge value="READY" /> No venue-level setup issues found</div>}</div></Panel>
    <div className="platform-grid platform-grid--sidebar platform-overview-grid"><Panel title="Recent platform activity" description="High-impact administrative changes made through Vynic." action={<Link className="platform-text-link" to="/admin/audit">View audit log</Link>}>{audit.isPending ? <LoadingState label="Loading activity" /> : audit.error ? <ErrorState error={errorMessage(audit.error)} retry={() => void audit.refetch()} /> : audit.data?.length ? <div className="platform-activity-list">{audit.data.map((event) => <div className="platform-activity" key={event.id}><span className="platform-activity__mark" /><div><strong>{humanize(event.action)}</strong><p>{event.actor.displayName} · {formatDateTime(event.createdAt)}</p></div><span className="platform-mono">{event.targetType}</span></div>)}</div> : <p className="platform-muted-copy">No platform changes have been recorded yet.</p>}</Panel><Panel title="Readiness snapshot" description="Loaded from the current Venue records."><div className="platform-snapshot-list">{details.slice(0, 6).map(({ venue, product, devices }) => <Link to={`/admin/venues/${venue.id}`} key={venue.id}><span><strong>{venue.name}</strong><small>{product.plan?.name ?? "No plan"} · {devices.length} device{devices.length === 1 ? "" : "s"}</small></span><span className={devices.some((device) => !device.lastSeenAt || device.status !== "ACTIVE") ? "platform-snapshot-issue" : "platform-snapshot-ok"}>{devices.length ? formatRelativeTime(devices.reduce<string | null>((latest, device) => !latest || (device.lastSeenAt && device.lastSeenAt > latest) ? device.lastSeenAt : latest, null)) : "No devices"}</span></Link>)}</div>{(venues.data?.total ?? 0) > details.length ? <p className="platform-limit-note">Showing the first {details.length} of {venues.data?.total} venues.</p> : null}</Panel></div>
  </>;
}
