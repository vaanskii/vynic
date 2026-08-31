import { useState } from "react";
import { Plus } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { platformApi } from "../api";
import { errorMessage, formatDateTime } from "../format";
import { Button } from "../components/Button";
import { Dialog } from "../components/Dialog";
import { Field, FormError, Input } from "../components/Form";
import { PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { Pagination, Table } from "../components/Table";

const PAGE_SIZE = 25;

export function OrganizationsPage() {
  const [offset, setOffset] = useState(0);
  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState("");
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: ["organizations", PAGE_SIZE, offset], queryFn: () => platformApi.organizations(PAGE_SIZE, offset) });
  const create = useMutation({
    mutationFn: () => platformApi.createOrganization(name),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["organizations"] });
      setCreateOpen(false); setName("");
    },
  });

  return (
    <>
      <PageHeader eyebrow="Tenant directory" title="Organizations" description="Restaurant groups that own one or more Vynic venues." actions={<Button tone="primary" onClick={() => setCreateOpen(true)}><Plus size={16} /> New organization</Button>} />
      <Panel>
        {query.isPending ? <LoadingState label="Loading organizations" /> : query.error ? <ErrorState error={errorMessage(query.error)} retry={() => void query.refetch()} /> : query.data.items.length === 0 ? (
          <EmptyState title="No organizations yet" body="Create the first tenant group before adding a venue." action={<Button tone="primary" onClick={() => setCreateOpen(true)}>Create organization</Button>} />
        ) : (
          <><Table><thead><tr><th>Organization</th><th>Venues</th><th>Updated</th><th aria-label="Actions" /></tr></thead><tbody>{query.data.items.map((organization) => (
            <tr key={organization.id}><td><div className="platform-table__primary"><strong>{organization.name}</strong><small>{organization.id}</small></div></td><td>{organization._count?.venues ?? 0}</td><td>{formatDateTime(organization.updatedAt)}</td><td><div className="platform-table__actions"><Link className="platform-text-link" to={`/admin/organizations/${organization.id}`}>Open</Link></div></td></tr>
          ))}</tbody></Table><Pagination total={query.data.total} limit={PAGE_SIZE} offset={offset} onChange={setOffset} /></>
        )}
      </Panel>
      <Dialog open={createOpen} onOpenChange={setCreateOpen} title="Create organization" description="This creates the tenant group only. No venue or other records are added automatically." footer={<><Button onClick={() => setCreateOpen(false)}>Cancel</Button><Button tone="primary" type="submit" form="create-organization" disabled={create.isPending}>{create.isPending ? "Creating…" : "Create"}</Button></>}>
        <form id="create-organization" className="platform-form" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}>
          <Field label="Organization name"><Input value={name} onChange={(event) => setName(event.target.value)} required maxLength={200} autoFocus /></Field>
          <FormError>{create.error ? errorMessage(create.error) : undefined}</FormError>
        </form>
      </Dialog>
    </>
  );
}
