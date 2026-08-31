import { useState } from "react";
import { PencilSimple } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useParams } from "react-router-dom";
import { platformApi } from "../api";
import { errorMessage, formatDateTime } from "../format";
import { Button } from "../components/Button";
import { Dialog } from "../components/Dialog";
import { Field, FormError, Input } from "../components/Form";
import { Detail, PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { StatusBadge } from "../components/StatusBadge";
import { Table } from "../components/Table";

export function OrganizationDetailPage() {
  const { organizationId = "" } = useParams();
  const [editOpen, setEditOpen] = useState(false);
  const [name, setName] = useState("");
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["organization", organizationId], queryFn: () => platformApi.organization(organizationId), enabled: Boolean(organizationId) });
  const update = useMutation({ mutationFn: () => platformApi.updateOrganization(organizationId, name), onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ["organization", organizationId] }); await queryClient.invalidateQueries({ queryKey: ["organizations"] }); setEditOpen(false); } });

  if (query.isPending) return <LoadingState label="Loading organization" />;
  if (query.error) return <ErrorState error={errorMessage(query.error)} retry={() => void query.refetch()} />;
  const organization = query.data;
  return <>
    <PageHeader eyebrow="Organization" title={organization.name} description="Tenant ownership and its venue directory." actions={<Button onClick={() => { setName(organization.name); setEditOpen(true); }}><PencilSimple size={16} /> Edit name</Button>} />
    <Panel title="Organization record"><dl className="platform-detail-grid"><Detail label="Organization ID" mono>{organization.id}</Detail><Detail label="Created">{formatDateTime(organization.createdAt)}</Detail><Detail label="Updated">{formatDateTime(organization.updatedAt)}</Detail></dl></Panel>
    <Panel title="Venues" description="Locations owned by this organization.">
      {organization.venues?.length ? <Table><thead><tr><th>Venue</th><th>Status</th><th>Timezone</th><th>Currency</th><th aria-label="Actions" /></tr></thead><tbody>{organization.venues.map((venue) => <tr key={venue.id}><td><div className="platform-table__primary"><strong>{venue.name}</strong><small>{venue.id}</small></div></td><td><StatusBadge value={venue.status} /></td><td>{venue.timezone}</td><td>{venue.currency}</td><td><div className="platform-table__actions"><Link className="platform-text-link" to={`/admin/venues/${venue.id}`}>Open</Link></div></td></tr>)}</tbody></Table> : <EmptyState title="No venues in this organization" body="Create a venue from the Venues directory and assign it to this organization." action={<Link className="platform-text-link" to="/admin/venues">Go to Venues</Link>} />}
    </Panel>
    <Dialog open={editOpen} onOpenChange={setEditOpen} title="Edit organization" footer={<><Button onClick={() => setEditOpen(false)}>Cancel</Button><Button tone="primary" type="submit" form="edit-organization" disabled={update.isPending}>Save changes</Button></>}>
      <form id="edit-organization" className="platform-form" onSubmit={(event) => { event.preventDefault(); update.mutate(); }}><Field label="Organization name"><Input value={name} onChange={(event) => setName(event.target.value)} required maxLength={200} /></Field><FormError>{update.error ? errorMessage(update.error) : undefined}</FormError></form>
    </Dialog>
  </>;
}
