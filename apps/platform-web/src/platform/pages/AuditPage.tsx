import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { platformApi } from "../api";
import { errorMessage, formatDateTime, humanize } from "../format";
import { PageHeader, Panel } from "../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../components/State";
import { Table } from "../components/Table";
import { Button } from "../components/Button";

const PAGE_SIZE = 50;

export function AuditPage() {
  const [offset, setOffset] = useState(0);
  const query = useQuery({ queryKey: ["audit", PAGE_SIZE, offset], queryFn: () => platformApi.audit(PAGE_SIZE, offset) });
  return <><PageHeader eyebrow="Platform activity" title="Audit log" description="Administrative actions in the Vynic control plane—not restaurant operational activity." /><Panel>{query.isPending ? <LoadingState label="Loading audit events" /> : query.error ? <ErrorState error={errorMessage(query.error)} retry={() => void query.refetch()} /> : query.data.length === 0 ? <EmptyState title="No audit events on this page" body={offset ? "Return to the previous page." : "No platform mutations have been recorded yet."} /> : <><Table><thead><tr><th>Time</th><th>Action</th><th>Actor</th><th>Target</th><th>Safe metadata</th></tr></thead><tbody>{query.data.map((event) => <tr key={event.id}><td>{formatDateTime(event.createdAt)}</td><td><strong>{humanize(event.action)}</strong></td><td><div className="platform-table__primary"><strong>{event.actor.displayName}</strong><small>{event.actor.email}</small></div></td><td><div className="platform-table__primary"><strong>{event.targetType}</strong><small>{event.targetId}</small></div></td><td><code className="platform-metadata">{event.metadata ? JSON.stringify(event.metadata) : "—"}</code></td></tr>)}</tbody></Table><div className="platform-pagination"><span>Page {Math.floor(offset / PAGE_SIZE) + 1}</span><div><Button tone="quiet" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}>Previous</Button><Button tone="quiet" disabled={query.data.length < PAGE_SIZE} onClick={() => setOffset(offset + PAGE_SIZE)}>Next</Button></div></div></>}</Panel></>;
}
