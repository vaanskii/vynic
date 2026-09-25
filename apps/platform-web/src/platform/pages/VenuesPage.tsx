import { useState } from "react";
import { Plus } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { platformApi } from "../api";
import { errorMessage, formatDateTime } from "../format";
import { Button } from "../components/Button";
import { Dialog } from "../components/Dialog";
import { Field, FormError, Input, Select } from "../components/Form";
import { PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { StatusBadge } from "../components/StatusBadge";
import { Pagination, Table } from "../components/Table";

const PAGE_SIZE = 25;

export function VenuesPage() {
  const [offset, setOffset] = useState(0);
  const [organizationId, setOrganizationId] = useState("");
  const [createOpen, setCreateOpen] = useState(false);
  const [form, setForm] = useState({ organizationId: "", name: "", timezone: "Asia/Tbilisi", currency: "GEL" });
  const queryClient = useQueryClient();
  const organizations = useQuery({ queryKey: ["organizations", 200, 0], queryFn: () => platformApi.organizations(200, 0) });
  const venues = useQuery({ queryKey: ["venues", { limit: PAGE_SIZE, offset, organizationId }], queryFn: () => platformApi.venues({ limit: PAGE_SIZE, offset, organizationId: organizationId || undefined }) });
  const create = useMutation({ mutationFn: () => platformApi.createVenue(form), onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ["venues"] }); await queryClient.invalidateQueries({ queryKey: ["organizations"] }); setCreateOpen(false); setForm({ organizationId: "", name: "", timezone: "Asia/Tbilisi", currency: "GEL" }); } });

  return <>
    <PageHeader eyebrow="Location directory" title="Venues" description="Every restaurant location and its platform-level status." actions={<Button tone="primary" onClick={() => setCreateOpen(true)}><Plus size={16} /> New venue</Button>} />
    <Panel title="All venues" action={<label className="platform-inline-filter"><span>Organization</span><Select value={organizationId} onChange={(event) => { setOrganizationId(event.target.value); setOffset(0); }}><option value="">All organizations</option>{organizations.data?.items.map((organization) => <option value={organization.id} key={organization.id}>{organization.name}</option>)}</Select></label>}>
      {venues.isPending ? <LoadingState label="Loading venues" /> : venues.error ? <ErrorState error={errorMessage(venues.error)} retry={() => void venues.refetch()} /> : venues.data.items.length === 0 ? <EmptyState title="No venues found" body={organizationId ? "This organization has no venues." : "Create the first location to begin configuring Vynic."} /> : <><Table><thead><tr><th>Venue</th><th>Status</th><th>Organization</th><th>Locale</th><th>Updated</th><th aria-label="Actions" /></tr></thead><tbody>{venues.data.items.map((venue) => { const organization = organizations.data?.items.find((item) => item.id === venue.organizationId); return <tr key={venue.id}><td><div className="platform-table__primary"><strong>{venue.name}</strong><small>{venue.id}</small></div></td><td><StatusBadge value={venue.status} /></td><td>{organization?.name ?? venue.organizationId}</td><td>{venue.timezone}<br /><small>{venue.currency}</small></td><td>{formatDateTime(venue.updatedAt)}</td><td><div className="platform-table__actions"><Link className="platform-text-link" to={`/venues/${venue.id}`}>Control venue</Link></div></td></tr>; })}</tbody></Table><Pagination total={venues.data.total} offset={offset} limit={PAGE_SIZE} onChange={setOffset} /></>}
    </Panel>
    <Dialog open={createOpen} onOpenChange={setCreateOpen} title="Create venue" description="Creates only the location record. Plans, domains, devices, menus, and tables remain deliberate separate actions." footer={<><Button onClick={() => setCreateOpen(false)}>Cancel</Button><Button tone="primary" type="submit" form="create-venue" disabled={create.isPending}>Create venue</Button></>}>
      <form id="create-venue" className="platform-form" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}>
        <Field label="Organization"><Select value={form.organizationId} onChange={(event) => setForm({ ...form, organizationId: event.target.value })} required><option value="">Select organization</option>{organizations.data?.items.map((organization) => <option value={organization.id} key={organization.id}>{organization.name}</option>)}</Select></Field>
        <Field label="Venue name"><Input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} required maxLength={200} /></Field>
        <div className="platform-form-grid"><Field label="Timezone" hint="IANA timezone, for example Asia/Tbilisi"><Input value={form.timezone} onChange={(event) => setForm({ ...form, timezone: event.target.value })} required maxLength={64} /></Field><Field label="Currency" hint="Three-letter ISO code"><Input value={form.currency} onChange={(event) => setForm({ ...form, currency: event.target.value.toUpperCase() })} required minLength={3} maxLength={3} /></Field></div>
        <FormError>{create.error ? errorMessage(create.error) : undefined}</FormError>
      </form>
    </Dialog>
  </>;
}
