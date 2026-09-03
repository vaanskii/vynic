import { useQuery } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage, formatDateTime, humanize } from "../../format";
import { Panel } from "../../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../../components/State";
import { Table } from "../../components/Table";

export function VenueActivityTab({ venueId }: { venueId: string }) {
  const query = useQuery({ queryKey: ["audit", "venue", venueId], queryFn: () => platformApi.audit(100, 0, undefined, venueId) });
  return <Panel title="Venue activity" description="Platform changes for this venue, including device lifecycle events.">{query.isPending ? <LoadingState label="Loading venue activity" /> : query.error ? <ErrorState error={errorMessage(query.error)} retry={() => void query.refetch()} /> : query.data.length === 0 ? <EmptyState title="No venue activity yet" body="Platform changes for this venue will appear here." /> : <Table><thead><tr><th>Time</th><th>Action</th><th>Actor</th><th>Target</th><th>Details</th></tr></thead><tbody>{query.data.map((event) => <tr key={event.id}><td>{formatDateTime(event.createdAt)}</td><td><strong>{humanize(event.action)}</strong></td><td>{event.actor.displayName}</td><td><div className="platform-table__primary"><strong>{event.targetType}</strong><small>{event.targetId}</small></div></td><td><code className="platform-metadata">{event.metadata ? JSON.stringify(event.metadata) : "—"}</code></td></tr>)}</tbody></Table>}</Panel>;
}
