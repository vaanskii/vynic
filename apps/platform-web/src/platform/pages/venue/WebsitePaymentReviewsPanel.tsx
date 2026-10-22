import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage } from "../../format";
import { Panel } from "../../components/Page";
import { Button } from "../../components/Button";
import { EmptyState, ErrorState, LoadingState } from "../../components/State";
import { Table, Pagination } from "../../components/Table";

const money = (value: string | null, currency: string | null) => {
  if (!value || !/^\d+$/.test(value) || !currency) return "Unknown";
  const digits = value.padStart(3, "0");
  return `${digits.slice(0, -2)}.${digits.slice(-2)} ${currency}`;
};
export function WebsitePaymentReviewsPanel({ venueId }: { venueId: string }) {
  const [offset, setOffset] = useState(0);
  const query = useQuery({
    queryKey: ["website-payment-reviews", venueId, offset],
    queryFn: () => platformApi.websitePaymentReviews(venueId, offset),
  });
  return (
    <Panel
      title="Booking payment review"
      description="The restaurant owner decides financial exceptions; Vynic support helps verify the records. Review never issues a refund or restores an expired booking automatically."
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
        <LoadingState />
      ) : query.error ? (
        <ErrorState
          error={errorMessage(query.error)}
          retry={() => void query.refetch()}
        />
      ) : query.data?.items.length === 0 ? (
        <EmptyState
          title="No unresolved booking payments"
          body="Uncertain, late and historical payment cases appear here."
        />
      ) : query.data ? (
        <>
          <Table>
            <thead>
              <tr>
                <th>Booking</th>
                <th>Review reason</th>
                <th>Expected / paid / refunded</th>
                <th>Provider reference</th>
              </tr>
            </thead>
            <tbody>
              {query.data.items.map((row) => (
                <tr key={row.bookingId}>
                  <td className="platform-mono">
                    {row.bookingId}
                    <br />
                    {row.date.slice(0, 10)} · {row.timeSlot}
                    <br />
                    {row.bookingStatus} · {row.paymentState}
                  </td>
                  <td>{row.reason.replaceAll("_", " ")}</td>
                  <td>
                    {money(row.expectedMinor, row.currency)} /{" "}
                    {money(row.grossPaidMinor, row.currency)} /{" "}
                    {money(row.refundedMinor, row.currency)}
                  </td>
                  <td className="platform-mono">
                    {row.paymentId ?? "Unknown"}
                  </td>
                </tr>
              ))}
            </tbody>
          </Table>
          <Pagination
            total={query.data.total}
            offset={offset}
            limit={query.data.limit}
            onChange={setOffset}
          />
        </>
      ) : null}
    </Panel>
  );
}
