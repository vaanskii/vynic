import type { Venue } from "../../types";
import { formatDateTime } from "../../format";
import { Detail, Panel } from "../../components/Page";
import { StatusBadge } from "../../components/StatusBadge";

export function VenueOverviewTab({ venue }: { venue: Venue }) {
  return <div className="platform-grid platform-grid--2"><Panel title="Venue record" description="Identity and ownership used across platform operations."><dl className="platform-detail-grid"><Detail label="Venue ID" mono>{venue.id}</Detail><Detail label="Organization">{venue.organization?.name ?? venue.organizationId}</Detail><Detail label="Status"><StatusBadge value={venue.status} /></Detail><Detail label="Timezone">{venue.timezone}</Detail><Detail label="Currency">{venue.currency}</Detail><Detail label="Updated">{formatDateTime(venue.updatedAt)}</Detail></dl></Panel><Panel title="Lifecycle" description="This record is retained; the control plane does not offer hard delete."><div className="platform-lifecycle"><div><span>Created</span><strong>{formatDateTime(venue.createdAt)}</strong></div><div><span>Last changed</span><strong>{formatDateTime(venue.updatedAt)}</strong></div></div></Panel></div>;
}
