import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../api";
import { useAuth } from "../auth";
import { errorMessage } from "../format";
import { Button } from "../components/Button";
import { PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { StatusBadge } from "../components/StatusBadge";

export function PlansPage() {
  const { actor } = useAuth();
  const client = useQueryClient();
  const query = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  const addWebsite = useMutation({
    mutationFn: platformApi.ensureWebsitePlan,
    onSuccess: async () => { await client.invalidateQueries({ queryKey: ["plans"] }); },
  });
  return <>
    <PageHeader eyebrow="Product catalogue" title="Plans" description="Commercial packages. Assign a plan on the venue’s Product tab." />
    {query.isPending ? <LoadingState label="Loading plans" /> : query.error ? <ErrorState error={errorMessage(query.error)} retry={() => void query.refetch()} /> : <>
      {!query.data.some(plan => plan.key === "WEBSITE_ONLY") && actor?.role === "SUPER_ADMIN" && <Panel title="Website only" description="Restaurant website and Cloud menu management, without POS or Manager App.">
        <Button tone="primary" loading={addWebsite.isPending} onClick={() => addWebsite.mutate()}>Add Website-only plan</Button>
        {addWebsite.error && <p role="alert">{errorMessage(addWebsite.error)}</p>}
      </Panel>}
      {query.data.length === 0 ? <Panel><EmptyState title="No plans configured" body="Add the Website-only plan to get started." /></Panel> : <div className="platform-card-grid">{query.data.map((plan) => <Panel key={plan.id} title={plan.name} action={<StatusBadge value={plan.status} />}>
        <p className="platform-mono platform-card-key">{plan.key}</p>
        {plan.key === "WEBSITE_ONLY" && <p>Restaurant website and Cloud menu management. No POS or Manager App.</p>}
        <div className="platform-chip-list">{plan.features.length ? plan.features.map(({ feature }) => <span key={feature.key}>{feature.name}</span>) : <small>No included features</small>}</div>
      </Panel>)}</div>}
    </>}
  </>;
}
