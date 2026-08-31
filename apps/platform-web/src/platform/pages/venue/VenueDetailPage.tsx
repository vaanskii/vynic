import { useState } from "react";
import { PencilSimple, Power } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Navigate, NavLink, useParams } from "react-router-dom";
import { platformApi } from "../../api";
import { errorMessage } from "../../format";
import { Button } from "../../components/Button";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { Dialog } from "../../components/Dialog";
import { Field, FormError, Input } from "../../components/Form";
import { PageHeader } from "../../components/Page";
import { ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";
import { VenueActivityTab } from "./VenueActivityTab";
import { VenueDevicesTab } from "./VenueDevicesTab";
import { VenueOverviewTab } from "./VenueOverviewTab";
import { VenueProductTab } from "./VenueProductTab";
import { VenueWebsiteTab } from "./VenueWebsiteTab";

const tabs = ["overview", "product", "website", "devices", "activity"] as const;

export function VenueDetailPage() {
  const { venueId = "", tab = "overview" } = useParams();
  const queryClient = useQueryClient();
  const [editOpen, setEditOpen] = useState(false);
  const [confirmStatus, setConfirmStatus] = useState(false);
  const venue = useQuery({ queryKey: ["venue", venueId], queryFn: () => platformApi.venue(venueId), enabled: Boolean(venueId) });
  const [form, setForm] = useState({ name: "", timezone: "", currency: "" });
  const update = useMutation({ mutationFn: () => platformApi.updateVenue(venueId, form), onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ["venue", venueId] }); await queryClient.invalidateQueries({ queryKey: ["venues"] }); setEditOpen(false); } });
  const status = useMutation({ mutationFn: () => platformApi.setVenueStatus(venueId, venue.data?.status === "ACTIVE" ? "DISABLED" : "ACTIVE"), onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ["venue", venueId] }); await queryClient.invalidateQueries({ queryKey: ["venues"] }); setConfirmStatus(false); } });

  if (venue.isPending) return <LoadingState label="Loading venue" />;
  if (venue.error) return <ErrorState error={errorMessage(venue.error)} retry={() => void venue.refetch()} />;
  const record = venue.data;
  const currentTab = tabs.includes(tab as (typeof tabs)[number]) ? tab : "overview";
  if (currentTab !== tab) return <Navigate to={`/venues/${venueId}`} replace />;

  return <>
    <PageHeader eyebrow={`${record.organization?.name ?? record.organizationId} / Venue`} title={record.name} description="Platform-level configuration and infrastructure for this location." actions={<><StatusBadge value={record.status} /><Button onClick={() => { setForm({ name: record.name, timezone: record.timezone, currency: record.currency }); setEditOpen(true); }}><PencilSimple size={16} /> Edit details</Button><Button tone={record.status === "ACTIVE" ? "danger" : "secondary"} onClick={() => setConfirmStatus(true)}><Power size={16} /> {record.status === "ACTIVE" ? "Disable" : "Enable"}</Button></>} />
    <nav className="platform-tabs" aria-label="Venue sections">{tabs.map((name) => <NavLink key={name} end={name === "overview"} className={({ isActive }) => isActive ? "is-active" : ""} to={name === "overview" ? `/venues/${venueId}` : `/venues/${venueId}/${name}`}>{name[0].toUpperCase() + name.slice(1)}</NavLink>)}</nav>
    {currentTab === "overview" ? <VenueOverviewTab venue={record} /> : null}
    {currentTab === "product" ? <VenueProductTab venueId={venueId} /> : null}
    {currentTab === "website" ? <VenueWebsiteTab venueId={venueId} /> : null}
    {currentTab === "devices" ? <VenueDevicesTab venueId={venueId} venueName={record.name} /> : null}
    {currentTab === "activity" ? <VenueActivityTab venueId={venueId} /> : null}
    <Dialog open={editOpen} onOpenChange={setEditOpen} title="Edit venue details" description="Basic location metadata only. Product and infrastructure settings live in their own tabs." footer={<><Button onClick={() => setEditOpen(false)}>Cancel</Button><Button tone="primary" type="submit" form="edit-venue" disabled={update.isPending}>Save changes</Button></>}>
      <form id="edit-venue" className="platform-form" onSubmit={(event) => { event.preventDefault(); update.mutate(); }}><Field label="Venue name"><Input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} required /></Field><div className="platform-form-grid"><Field label="Timezone"><Input value={form.timezone} onChange={(event) => setForm({ ...form, timezone: event.target.value })} required maxLength={64} /></Field><Field label="Currency"><Input value={form.currency} onChange={(event) => setForm({ ...form, currency: event.target.value.toUpperCase() })} required minLength={3} maxLength={3} /></Field></div><FormError>{update.error ? errorMessage(update.error) : undefined}</FormError></form>
    </Dialog>
    <ConfirmDialog open={confirmStatus} onOpenChange={setConfirmStatus} title={`${record.status === "ACTIVE" ? "Disable" : "Enable"} ${record.name}?`} description={record.status === "ACTIVE" ? "Devices will stop authenticating and public host resolution will stop for this venue. The venue data is retained and can be enabled later." : "Device authentication and public host resolution may resume immediately for this venue."} confirmLabel={record.status === "ACTIVE" ? "Disable venue" : "Enable venue"} danger={record.status === "ACTIVE"} pending={status.isPending} onConfirm={() => status.mutate()} />
  </>;
}
