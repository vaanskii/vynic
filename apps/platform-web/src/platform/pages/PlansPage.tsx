import { useQuery } from "@tanstack/react-query";
import { platformApi } from "../api";
import { errorMessage } from "../format";
import { PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { StatusBadge } from "../components/StatusBadge";

export function PlansPage() {
  const query = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  return <><PageHeader eyebrow="Product catalogue" title="Plans" description="Read-only commercial packages. Venue assignment happens on each venue’s Product tab." />{query.isPending ? <LoadingState label="Loading plans" /> : query.error ? <ErrorState error={errorMessage(query.error)} retry={() => void query.refetch()} /> : query.data.length === 0 ? <Panel><EmptyState title="No plans configured" body="The backend catalogue is empty." /></Panel> : <div className="platform-card-grid">{query.data.map((plan) => <Panel key={plan.id} title={plan.name} action={<StatusBadge value={plan.status} />}><p className="platform-mono platform-card-key">{plan.key}</p><div className="platform-chip-list">{plan.features.length ? plan.features.map(({ feature }) => <span key={feature.key}>{feature.name}</span>) : <small>No included features</small>}</div></Panel>)}</div>}</>;
}
