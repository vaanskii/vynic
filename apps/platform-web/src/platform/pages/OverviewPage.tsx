import { Buildings, ChartDonut, SlidersHorizontal, Storefront } from "@phosphor-icons/react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { platformApi } from "../api";
import { errorMessage, formatDateTime, humanize } from "../format";
import { PageHeader, Panel } from "../components/Page";
import { ErrorState, LoadingState } from "../components/State";

export function OverviewPage() {
  const organizations = useQuery({ queryKey: ["organizations", 1, 0], queryFn: () => platformApi.organizations(1, 0) });
  const venues = useQuery({ queryKey: ["venues", { limit: 1, offset: 0 }], queryFn: () => platformApi.venues({ limit: 1 }) });
  const plans = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  const features = useQuery({ queryKey: ["features"], queryFn: platformApi.features });
  const audit = useQuery({ queryKey: ["audit", 8, 0], queryFn: () => platformApi.audit(8, 0) });

  const metricQueries = [organizations, venues, plans, features];
  if (metricQueries.some((query) => query.isPending)) return <LoadingState label="Loading platform overview" />;
  const failed = metricQueries.find((query) => query.error);
  if (failed) return <ErrorState error={errorMessage(failed.error)} retry={() => metricQueries.forEach((query) => void query.refetch())} />;

  const metrics = [
    { label: "Organizations", value: organizations.data?.total ?? 0, note: "Tenant groups", icon: Buildings, to: "/organizations" },
    { label: "Venues", value: venues.data?.total ?? 0, note: "Managed locations", icon: Storefront, to: "/venues" },
    { label: "Plans", value: plans.data?.length ?? 0, note: "Commercial packages", icon: ChartDonut, to: "/plans" },
    { label: "Features", value: features.data?.length ?? 0, note: "Platform capabilities", icon: SlidersHorizontal, to: "/features" },
  ];

  return (
    <>
      <PageHeader eyebrow="Platform overview" title="Good control starts with the real state." description="Live directory and product catalogue counts from the control-plane API. No billing or operational metrics are inferred here." />
      <div className="platform-grid platform-grid--metrics">
        {metrics.map(({ label, value, note, icon: Icon, to }) => (
          <Link className="platform-metric" to={to} key={label}>
            <div className="platform-metric__top"><span>{label}</span><Icon size={19} weight="duotone" /></div>
            <strong>{value}</strong><p>{note}</p>
          </Link>
        ))}
      </div>
      <div className="platform-grid platform-grid--sidebar platform-overview-grid">
        <Panel title="Recent platform activity" description="Mutations made through the Vynic control plane." action={<Link className="platform-text-link" to="/audit">View audit log</Link>}>
          {audit.isPending ? <LoadingState label="Loading activity" /> : audit.error ? <ErrorState error={errorMessage(audit.error)} retry={() => void audit.refetch()} /> : audit.data?.length ? (
            <div className="platform-activity-list">
              {audit.data.map((event) => (
                <div className="platform-activity" key={event.id}>
                  <span className="platform-activity__mark" />
                  <div><strong>{humanize(event.action)}</strong><p>{event.actor.displayName} · {formatDateTime(event.createdAt)}</p></div>
                  <span className="platform-mono">{event.targetType}</span>
                </div>
              ))}
            </div>
          ) : <p className="platform-muted-copy">No platform mutations have been recorded yet.</p>}
        </Panel>
        <Panel title="Operational focus" description="The venue page is the main control surface.">
          <div className="platform-focus-list">
            <Link to="/venues"><strong>Venue configuration</strong><span>Plans, features, website, devices, and activity</span></Link>
            <Link to="/organizations"><strong>Tenant directory</strong><span>Organization ownership and venue grouping</span></Link>
            <Link to="/devices"><strong>Edge infrastructure</strong><span>Credentials, device status, and connection tests</span></Link>
          </div>
        </Panel>
      </div>
    </>
  );
}
