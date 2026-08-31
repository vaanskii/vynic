import { useQuery } from "@tanstack/react-query";
import { platformApi } from "../api";
import { errorMessage } from "../format";
import { PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { Table } from "../components/Table";

export function FeaturesPage() {
  const query = useQuery({ queryKey: ["features"], queryFn: platformApi.features });
  return <><PageHeader eyebrow="Product catalogue" title="Features" description="Vynic-controlled capability identifiers. Venue-specific exceptions are managed as explicit overrides." /><Panel>{query.isPending ? <LoadingState label="Loading features" /> : query.error ? <ErrorState error={errorMessage(query.error)} retry={() => void query.refetch()} /> : query.data.length === 0 ? <EmptyState title="No features configured" body="The backend feature catalogue is empty." /> : <Table><thead><tr><th>Feature</th><th>Identifier</th><th>Authority</th></tr></thead><tbody>{query.data.map((feature) => <tr key={feature.id}><td><strong>{feature.name}</strong></td><td className="platform-mono">{feature.key}</td><td>Vynic platform</td></tr>)}</tbody></Table>}</Panel></>;
}
