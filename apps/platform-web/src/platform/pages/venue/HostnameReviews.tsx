import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { useAuth } from "../../auth";
import { Panel } from "../../components/Page";
import { Button } from "../../components/Button";
import { Field, Input } from "../../components/Form";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { ErrorState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";
import { Table } from "../../components/Table";
import { errorMessage, formatDateTime } from "../../format";
/**
 * Paid owners' SaaS address change requests. Approval re-checks availability
 * on the server and moves the one SaaS binding; rejection changes nothing.
 */
export function HostnameReviews({
  venueId,
  saas,
  currentHostname,
}: {
  venueId: string;
  saas: boolean;
  currentHostname: string | null;
}) {
  const { actor } = useAuth();
  const client = useQueryClient();
  const requests = useQuery({
    queryKey: ["hostname-requests", venueId],
    queryFn: () => platformApi.hostnameRequests(venueId),
  });
  const [status, setStatus] = useState("");
  const [reason, setReason] = useState("");
  const pending = requests.data?.find((r) => r.status === "PENDING");
  const decided = requests.data?.filter((r) => r.status !== "PENDING") ?? [];
  const review = useMutation({
    mutationFn: () =>
      platformApi.reviewHostname(venueId, pending!.id, status, reason),
    onSuccess: async () => {
      setStatus("");
      setReason("");
      await Promise.all(
        ["hostname-requests", "domains", "product", "audit"].map((key) =>
          client.invalidateQueries({
            queryKey: key === "audit" ? [key] : [key, venueId],
          }),
        ),
      );
    },
  });
  if (!saas && requests.data?.length === 0) return null;
  return (
    <Panel
      title="Hostname change request"
      description="Previous requests remain available for review. New address changes are handled by Platform Admin after customers contact support."
    >
      {requests.isPending ? (
        <p>Loading requests…</p>
      ) : requests.error ? (
        <ErrorState
          error={errorMessage(requests.error)}
          retry={() => void requests.refetch()}
        />
      ) : pending ? (
        <>
          <p>
            {pending.currentHostname ?? currentHostname ?? "—"} →{" "}
            <strong>{pending.hostname}</strong> ·{" "}
            <StatusBadge value="PENDING" />
          </p>
          <p>Requested {formatDateTime(pending.createdAt)}</p>
          {actor?.role !== "SUPPORT_READONLY" && (
            <>
              <Field label="Review reason">
                <Input
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  maxLength={1000}
                />
              </Field>
              <Button
                disabled={!reason.trim()}
                onClick={() => setStatus("APPROVED")}
              >
                Approve
              </Button>
              <Button
                disabled={!reason.trim()}
                onClick={() => setStatus("REJECTED")}
              >
                Reject
              </Button>
            </>
          )}
        </>
      ) : (
        <p>No pending hostname change.</p>
      )}
      {decided.length > 0 && (
        <Table>
          <thead>
            <tr>
              <th>Requested</th>
              <th>From</th>
              <th>Decision</th>
              <th>Reviewed</th>
              <th>Note</th>
            </tr>
          </thead>
          <tbody>
            {decided.slice(0, 5).map((r) => (
              <tr key={r.id}>
                <td>{r.hostname}</td>
                <td>{r.currentHostname ?? "—"}</td>
                <td>
                  <StatusBadge value={r.status} />
                </td>
                <td>{formatDateTime(r.reviewedAt)}</td>
                <td>{r.reason ?? ""}</td>
              </tr>
            ))}
          </tbody>
        </Table>
      )}
      <ConfirmDialog
        open={!!status}
        onOpenChange={(open) => {
          if (!open) setStatus("");
        }}
        title={
          status === "APPROVED"
            ? "Approve hostname change?"
            : "Reject hostname change?"
        }
        description={
          status === "APPROVED"
            ? `The current SaaS address will be replaced with ${pending?.hostname}. Availability and paid access are checked again.`
            : "The current address stays unchanged."
        }
        confirmLabel={status === "APPROVED" ? "Approve" : "Reject"}
        pending={review.isPending}
        error={review.error ? errorMessage(review.error) : undefined}
        onConfirm={() => review.mutate()}
      />
    </Panel>
  );
}
