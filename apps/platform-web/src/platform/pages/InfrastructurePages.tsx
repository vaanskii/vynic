import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { platformApi } from "../api";
import { errorMessage, formatRelativeTime } from "../format";
import { PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { StatusBadge } from "../components/StatusBadge";
import { Table } from "../components/Table";

export function DevicesPage() {
  const venues = useQuery({ queryKey: ["venues", { limit: 200, offset: 0 }], queryFn: () => platformApi.venues({ limit: 200 }) });
  const devices = useQuery({ queryKey: ["devices", "all", venues.data?.items.map((venue) => venue.id)], enabled: Boolean(venues.data), queryFn: async () => Promise.all((venues.data?.items ?? []).map(async (venue) => ({ venue, devices: await platformApi.devices(venue.id) }))) });
  if (venues.isPending || devices.isPending) return <LoadingState label="Loading device inventory" />;
  const failed = venues.error ?? devices.error;
  if (failed) return <ErrorState error={errorMessage(failed)} retry={() => { void venues.refetch(); void devices.refetch(); }} />;
  if (!venues.data || !devices.data) return <LoadingState label="Loading device inventory" />;
  const rows = devices.data.flatMap(({ venue, devices: items }) => items.map((device) => ({ venue, device })));
  return <><PageHeader eyebrow="Edge infrastructure" title="Devices" description="Cross-venue POS device inventory. Lifecycle operations remain on each venue’s Devices tab." />{venues.data.total > venues.data.items.length ? <p className="platform-limit-note">Showing devices for the first {venues.data.items.length} of {venues.data.total} venues. Open a venue directly for complete management.</p> : null}<Panel>{rows.length === 0 ? <EmptyState title="No devices registered" body="Open a venue to issue its first POS device credential." /> : <Table><thead><tr><th>Device</th><th>Venue</th><th>Status</th><th>Activity</th><th aria-label="Actions" /></tr></thead><tbody>{rows.map(({ venue, device }) => <tr key={device.id}><td><div className="platform-table__primary"><strong>{device.displayName}</strong><small>{device.installationId}</small></div></td><td>{venue.name}</td><td><StatusBadge value={device.status} /></td><td>{formatRelativeTime(device.lastSeenAt)}</td><td><div className="platform-table__actions"><Link className="platform-text-link" to={`/admin/venues/${venue.id}/devices`}>Manage</Link></div></td></tr>)}</tbody></Table>}</Panel></>;
}

export function DomainsPage() {
  const venues = useQuery({ queryKey: ["venues", { limit: 200, offset: 0 }], queryFn: () => platformApi.venues({ limit: 200 }) });
  const domains = useQuery({ queryKey: ["domains", "all", venues.data?.items.map((venue) => venue.id)], enabled: Boolean(venues.data), queryFn: async () => Promise.all((venues.data?.items ?? []).map(async (venue) => ({ venue, domains: await platformApi.domains(venue.id) }))) });
  if (venues.isPending || domains.isPending) return <LoadingState label="Loading domain inventory" />;
  const failed = venues.error ?? domains.error;
  if (failed) return <ErrorState error={errorMessage(failed)} retry={() => { void venues.refetch(); void domains.refetch(); }} />;
  if (!venues.data || !domains.data) return <LoadingState label="Loading domain inventory" />;
  const rows = domains.data.flatMap(({ venue, domains: items }) => items.map((domain) => ({ venue, domain })));
  return <><PageHeader eyebrow="Public infrastructure" title="Domains" description="Registered hostnames and their owning venues. DNS and TLS are managed outside this control plane." />{venues.data.total > venues.data.items.length ? <p className="platform-limit-note">Showing domains for the first {venues.data.items.length} of {venues.data.total} venues.</p> : null}<Panel>{rows.length === 0 ? <EmptyState title="No domains registered" body="Open a venue’s Website tab to register a hostname." /> : <Table><thead><tr><th>Hostname</th><th>Venue</th><th>Status</th><th aria-label="Actions" /></tr></thead><tbody>{rows.map(({ venue, domain }) => <tr key={domain.id}><td><div className="platform-table__primary"><strong>{domain.hostname}</strong><small>{domain.id}</small></div></td><td>{venue.name}</td><td><StatusBadge value={domain.status} /></td><td><div className="platform-table__actions"><Link className="platform-text-link" to={`/admin/venues/${venue.id}/website`}>Manage</Link></div></td></tr>)}</tbody></Table>}</Panel></>;
}
