import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage } from "../../format";
import { Button } from "../../components/Button";
import { Panel } from "../../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../../components/State";
import { Pagination, Table } from "../../components/Table";

const outcome = (status: string) =>
  ({
    PENDING: "Waiting for queue",
    QUEUED: "Queued · awaiting POS",
    CLAIMED: "Claimed · awaiting POS result",
    SUCCEEDED: "POS acknowledged",
    FAILED: "Failed · reconcile with POS",
    ATTENTION: "Needs operator review",
    UNKNOWN: "Outcome unknown · reconcile with POS",
    DELIVERED_LEGACY: "Accepted by legacy POS",
  })[status] ?? status;

export function WebsiteDeliveriesPanel({ venueId }: { venueId: string }) {
  const [offset, setOffset] = useState(0);
  const query = useQuery({
    queryKey: ["website-deliveries", venueId, offset],
    queryFn: () => platformApi.websiteDeliveries(venueId, offset),
    refetchInterval: 15_000,
  });
  return (
    <Panel
      title="Website bookings · POS delivery"
      description="Queue admission and POS acknowledgment are separate. Inspect uncertain outcomes with support before issuing new work."
      action={
        <Button
          tone="quiet"
          disabled={query.isFetching}
          onClick={() => void query.refetch()}
        >
          Refresh
        </Button>
      }
    >
      {query.isPending ? (
        <LoadingState label="Loading POS deliveries" />
      ) : query.error ? (
        <ErrorState
          error={errorMessage(query.error)}
          retry={() => void query.refetch()}
        />
      ) : query.data ? (
        <>
          {!query.data.primarySelected ? (
            <p>
              No Primary POS selected. Edge work remains queued until an
              operator selects an active device; legacy delivery is shown
              separately.
            </p>
          ) : null}
          {query.data.items.length === 0 ? (
            <EmptyState
              title="No website deliveries"
              body="Confirmed bookings and unresolved handoffs will appear here."
            />
          ) : (
            <Table>
              <thead>
                <tr>
                  <th>Booking</th>
                  <th>Booking status</th>
                  <th>POS delivery</th>
                  <th>POS identity</th>
                </tr>
              </thead>
              <tbody>
                {query.data.items.map((booking) => (
                  <tr key={booking.id}>
                    <td>
                      <span className="platform-mono">{booking.id}</span>
                      <br />
                      {booking.date.slice(0, 10)} · {booking.timeSlot}
                    </td>
                    <td>{booking.bookingStatus}</td>
                    <td>
                      {booking.tracking === "UNTRACKED" ? (
                        <p>
                          Historical creation untracked · inspect POS; do not
                          replay
                        </p>
                      ) : null}
                      {booking.deliveries.map((delivery) => (
                        <p key={delivery.kind}>
                          {delivery.kind}: {outcome(delivery.status)}
                          {delivery.code ? (
                            <>
                              <br />
                              {delivery.code}
                            </>
                          ) : null}
                        </p>
                      ))}
                    </td>
                    <td className="platform-mono">
                      {booking.posReservationId ??
                        booking.deliveries[0]?.posReservationId ??
                        "Not assigned"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
          <Pagination
            total={query.data.total}
            offset={query.data.offset}
            limit={query.data.limit}
            onChange={setOffset}
          />
        </>
      ) : null}
    </Panel>
  );
}
