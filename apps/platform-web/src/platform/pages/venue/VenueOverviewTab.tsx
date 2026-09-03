import { CheckCircle, DesktopTower, Globe, Package, WarningCircle } from "@phosphor-icons/react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { platformApi } from "../../api";
import { errorMessage, formatDateTime, formatRelativeTime, humanize } from "../../format";
import type { Venue } from "../../types";
import { Detail, Panel } from "../../components/Page";
import { ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";

export function VenueOverviewTab({ venue }: { venue: Venue }) {
  const product = useQuery({ queryKey: ["product", venue.id], queryFn: () => platformApi.product(venue.id) });
  const domains = useQuery({ queryKey: ["domains", venue.id], queryFn: () => platformApi.domains(venue.id) });
  const devices = useQuery({ queryKey: ["devices", venue.id], queryFn: () => platformApi.devices(venue.id) });
  const activity = useQuery({ queryKey: ["audit", "venue", venue.id], queryFn: () => platformApi.audit(8, 0, undefined, venue.id) });

  const queries = [product, domains, devices, activity];
  if (queries.some((query) => query.isPending)) return <LoadingState label="Loading venue readiness" />;
  const failed = queries.find((query) => query.error);
  if (failed) return <ErrorState error={errorMessage(failed.error)} retry={() => queries.forEach((query) => void query.refetch())} />;
  if (!product.data || !domains.data || !devices.data || !activity.data) return <LoadingState label="Loading venue readiness" />;

  const activeDomains = domains.data.filter((domain) => domain.status === "ACTIVE");
  const neverSeen = devices.data.filter((device) => !device.lastSeenAt);
  const inactive = devices.data.filter((device) => device.status !== "ACTIVE");
  const websiteNeedsDomain = product.data.website.entitled && product.data.website.effectiveMode !== "NONE" && activeDomains.length === 0;
  const attention = [
    !product.data.plan ? { icon: Package, title: "No plan assigned", body: "Assign a plan before this venue can inherit product access.", to: `/admin/venues/${venue.id}/product`, action: "Review product" } : null,
    !product.data.website.consistent ? { icon: Globe, title: "Website configuration needs review", body: "Entitlement and configured mode do not agree.", to: `/admin/venues/${venue.id}/website`, action: "Review website" } : null,
    websiteNeedsDomain ? { icon: Globe, title: "Website has no active domain", body: "The website is configured, but no active hostname is registered.", to: `/admin/venues/${venue.id}/website`, action: "Manage domains" } : null,
    devices.data.length === 0 ? { icon: DesktopTower, title: "No devices registered", body: "Add the first POS device to start connecting this venue.", to: `/admin/venues/${venue.id}/devices`, action: "Manage devices" } : null,
    neverSeen.length > 0 ? { icon: DesktopTower, title: `${neverSeen.length} device${neverSeen.length === 1 ? "" : "s"} never connected`, body: "Review provisioning or connection setup.", to: `/admin/venues/${venue.id}/devices`, action: "Review devices" } : null,
    inactive.length > 0 ? { icon: WarningCircle, title: `${inactive.length} device${inactive.length === 1 ? " is" : "s are"} disabled or revoked`, body: "Check the device lifecycle before service depends on it.", to: `/admin/venues/${venue.id}/devices`, action: "Review lifecycle" } : null,
  ].filter(Boolean) as Array<{ icon: typeof Package; title: string; body: string; to: string; action: string }>;

  const latestDeviceSeen = devices.data.reduce<string | null>((latest, device) => !latest || (device.lastSeenAt && device.lastSeenAt > latest) ? device.lastSeenAt : latest, null);

  return <>
    <div className="platform-readiness-head"><div><p className="platform-eyebrow">Operational readiness</p><h2>{attention.length === 0 ? "Ready for the next step" : `${attention.length} item${attention.length === 1 ? "" : "s"} need attention`}</h2><p>Configuration, access, website, and device state from the control plane.</p></div><div className={`platform-readiness-state ${attention.length === 0 ? "is-ready" : "is-attention"}`}><span>{attention.length === 0 ? <CheckCircle size={18} weight="duotone" /> : <WarningCircle size={18} weight="duotone" />}</span>{attention.length === 0 ? "No configuration issues found" : "Review before handoff"}</div></div>
    {attention.length > 0 ? <Panel title="Attention" description="Each item links to the tab where it can be corrected."><div className="platform-attention-list">{attention.map(({ icon: Icon, title, body, to, action }) => <Link to={to} className="platform-attention" key={title}><span className="platform-attention__icon"><Icon size={18} weight="duotone" /></span><span><strong>{title}</strong><small>{body}</small></span><span className="platform-text-link">{action} →</span></Link>)}</div></Panel> : null}
    <div className="platform-grid platform-grid--2 platform-section-gap"><Panel title="Venue record" description="Identity and ownership used across platform operations."><dl className="platform-detail-grid"><Detail label="Venue ID" mono>{venue.id}</Detail><Detail label="Organization">{venue.organization?.name ?? venue.organizationId}</Detail><Detail label="Status"><StatusBadge value={venue.status} /></Detail><Detail label="Timezone">{venue.timezone}</Detail><Detail label="Currency">{venue.currency}</Detail><Detail label="Updated">{formatDateTime(venue.updatedAt)}</Detail></dl></Panel><Panel title="Readiness summary" description="The current effective state of this venue."><dl className="platform-detail-grid"><Detail label="Plan">{product.data.plan?.name ?? "Not assigned"}</Detail><Detail label="Effective features">{product.data.effectiveFeatures.length} enabled</Detail><Detail label="Website entitlement"><StatusBadge value={product.data.website.entitled ? "ENABLED" : "DISABLED"} /></Detail><Detail label="Configured mode">{product.data.website.configuredMode}</Detail><Detail label="Effective mode">{product.data.website.effectiveMode}</Detail><Detail label="Website consistency"><StatusBadge value={product.data.website.consistent ? "CONSISTENT" : "INCONSISTENT"} /></Detail><Detail label="Active domains">{activeDomains.length} of {domains.data.length}</Detail><Detail label="Devices">{devices.data.length}</Detail><Detail label="Active devices">{devices.data.filter((device) => device.status === "ACTIVE").length}</Detail><Detail label="Never connected">{neverSeen.length}</Detail><Detail label="Latest device activity">{formatRelativeTime(latestDeviceSeen)}</Detail></dl></Panel></div>
    <div className="platform-grid platform-grid--sidebar"><Panel title="Recent venue activity" description="Platform changes for this venue, including its Devices." action={<Link className="platform-text-link" to={`/admin/venues/${venue.id}/activity`}>View all activity</Link>}>{activity.data.length ? <div className="platform-activity-list">{activity.data.map((event) => <div className="platform-activity" key={event.id}><span className="platform-activity__mark" /><div><strong>{humanize(event.action)}</strong><p>{event.actor.displayName} · {formatDateTime(event.createdAt)}</p></div><span className="platform-mono">{event.targetType}</span></div>)}</div> : <p className="platform-muted-copy">No platform changes recorded yet.</p>}</Panel><Panel title="Lifecycle" description="This record is retained; disabling is the reversible control-plane action."><div className="platform-lifecycle"><div><span>Created</span><strong>{formatDateTime(venue.createdAt)}</strong></div><div><span>Last changed</span><strong>{formatDateTime(venue.updatedAt)}</strong></div></div></Panel></div>
  </>;
}
