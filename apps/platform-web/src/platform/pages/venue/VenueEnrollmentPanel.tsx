import { useState } from "react";
import { Copy, Plus, WarningCircle } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage, formatDateTime } from "../../format";
import type { DeviceEnrollment, EnrollmentStatus, IssuedEnrollment } from "../../types";
import { Button } from "../../components/Button";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { Dialog } from "../../components/Dialog";
import { Field, FormError, Input, Select } from "../../components/Form";
import { Panel } from "../../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";
import { Table } from "../../components/Table";

/**
 * What each state means to the person reading it.
 *
 * "Waiting for enrollment" rather than "pending", because the operator is
 * waiting for something specific to happen at a till. None of these is an
 * online/offline claim — that question is answered by the device's last seen
 * time, and only as far as it honestly can be.
 */
const STATUS_LABEL: Record<EnrollmentStatus, string> = {
  PENDING: "Waiting for enrollment",
  ENROLLED: "Enrolled",
  EXPIRED: "Expired",
  CANCELLED: "Cancelled",
};

export function VenueEnrollmentPanel({ venueId, venueName }: { venueId: string; venueName: string }) {
  const queryClient = useQueryClient();
  const enrollments = useQuery({
    queryKey: ["enrollments", venueId],
    queryFn: () => platformApi.enrollments(venueId),
    // While an invitation is outstanding the operator is watching this table
    // for it to flip. Polling stops the moment nothing is waiting.
    refetchInterval: (query) =>
      query.state.data?.some((row) => row.status === "PENDING") ? 4000 : false,
  });
  const [createOpen, setCreateOpen] = useState(false);
  const [form, setForm] = useState({ displayName: "", platform: "WINDOWS", ttlMinutes: "30" });
  const [issued, setIssued] = useState<IssuedEnrollment | null>(null);
  const [copied, setCopied] = useState(false);
  const [cancelling, setCancelling] = useState<DeviceEnrollment | null>(null);

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ["enrollments", venueId] });
    await queryClient.invalidateQueries({ queryKey: ["devices", venueId] });
    await queryClient.invalidateQueries({ queryKey: ["audit"] });
  };

  const create = useMutation({
    mutationFn: async () => {
      const result = await platformApi.createEnrollment(venueId, {
        displayName: form.displayName,
        platform: form.platform,
        ttlMinutes: Number(form.ttlMinutes),
      });
      setIssued(result);
      return result;
    },
    onSuccess: async () => {
      await refresh();
      setCreateOpen(false);
      setForm({ displayName: "", platform: "WINDOWS", ttlMinutes: "30" });
    },
  });

  const cancel = useMutation({
    mutationFn: (enrollment: DeviceEnrollment) => platformApi.cancelEnrollment(venueId, enrollment.id),
    onSuccess: async () => {
      await refresh();
      setCancelling(null);
    },
  });

  const closeCode = () => {
    setIssued(null);
    setCopied(false);
    create.reset();
  };

  return <>
    <Panel
      title="POS enrollment"
      description="An operator types a one-time code into the terminal. The device credential is issued by the backend and never passes through a person."
      action={<Button tone="primary" onClick={() => setCreateOpen(true)}><Plus size={16} /> Enrol a POS</Button>}
    >
      {enrollments.isPending ? <LoadingState label="Loading enrollments" />
        : enrollments.error ? <ErrorState error={errorMessage(enrollments.error)} retry={() => void enrollments.refetch()} />
        : enrollments.data.length === 0 ? <EmptyState title="No enrollments" body={`Create one to connect a new terminal to ${venueName}.`} />
        : <Table>
            <thead><tr><th>Terminal</th><th>Status</th><th>Expires</th><th aria-label="Actions" /></tr></thead>
            <tbody>{enrollments.data.map((enrollment) => <tr key={enrollment.id}>
              <td><div className="platform-table__primary">
                <strong>{enrollment.displayName}</strong>
                <small>{enrollment.platform} · code {enrollment.codeSelector}·····</small>
                <small>Created {formatDateTime(enrollment.createdAt)}</small>
              </div></td>
              <td><div className="platform-table__primary">
                <StatusBadge value={enrollment.status}>{STATUS_LABEL[enrollment.status]}</StatusBadge>
                {enrollment.redeemedAt ? <small>Enrolled {formatDateTime(enrollment.redeemedAt)}</small> : null}
                {enrollment.attemptCount > 0 && !enrollment.redeemedAt ? <small>{enrollment.attemptCount} failed attempt{enrollment.attemptCount === 1 ? "" : "s"}</small> : null}
              </div></td>
              <td>{formatDateTime(enrollment.expiresAt)}</td>
              <td><div className="platform-table__actions">
                {enrollment.status === "PENDING"
                  ? <Button tone="danger" onClick={() => setCancelling(enrollment)}>Cancel code</Button>
                  : null}
              </div></td>
            </tr>)}</tbody>
          </Table>}
    </Panel>

    <Dialog
      open={createOpen}
      onOpenChange={setCreateOpen}
      title="Enrol a POS"
      description="A one-time code will be shown once. Have the terminal in front of you before you continue."
      footer={<>
        <Button onClick={() => setCreateOpen(false)}>Cancel</Button>
        <Button tone="primary" type="submit" form="create-enrollment" disabled={create.isPending}>Create enrollment code</Button>
      </>}
    >
      <form id="create-enrollment" className="platform-form" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}>
        <Field label="Terminal name" hint="What this till will be called in the device list.">
          <Input value={form.displayName} onChange={(event) => setForm({ ...form, displayName: event.target.value })} required maxLength={200} autoFocus />
        </Field>
        <Field label="Platform">
          <Input value={form.platform} onChange={(event) => setForm({ ...form, platform: event.target.value.toUpperCase() })} required maxLength={32} />
        </Field>
        <Field label="Code valid for" hint="Shorter is safer. The code is single use whatever you pick.">
          <Select value={form.ttlMinutes} onChange={(event) => setForm({ ...form, ttlMinutes: event.target.value })}>
            <option value="15">15 minutes</option>
            <option value="30">30 minutes</option>
            <option value="60">1 hour</option>
            <option value="240">4 hours</option>
          </Select>
        </Field>
        <FormError>{create.error ? errorMessage(create.error) : undefined}</FormError>
      </form>
    </Dialog>

    <Dialog
      open={Boolean(issued)}
      onOpenChange={(open) => { if (!open) closeCode(); }}
      title="Enrollment code"
      description="Type this into the terminal. It works once, for this venue only."
      footer={<Button tone="primary" onClick={closeCode}>Done</Button>}
    >
      {issued ? <div className="platform-secret">
        <div className="platform-enrollment-code"><code>{issued.code}</code></div>
        <div className="platform-secret__actions">
          <Button onClick={async () => { await navigator.clipboard.writeText(issued.code); setCopied(true); }}>
            <Copy size={16} /> {copied ? "Copied" : "Copy code"}
          </Button>
        </div>
        <div className="platform-callout">
          <WarningCircle size={19} />
          <div>
            <strong>Shown once, single use</strong>
            <p>
              Only a verifier is stored, so this code cannot be read back. It expires {formatDateTime(issued.expiresAt)}
              {" "}and stops working the moment a terminal uses it. If it is lost, cancel it and create another.
            </p>
          </div>
        </div>
        <ol className="platform-steps">
          <li>On the POS, open <strong>Settings → Connection</strong>.</li>
          <li>Choose <strong>Connect this POS to Vynic</strong>.</li>
          <li>Enter this server's address, then the code above.</li>
          <li>This table shows <strong>Enrolled</strong> when the terminal has it.</li>
        </ol>
      </div> : null}
    </Dialog>

    <ConfirmDialog
      open={Boolean(cancelling)}
      onOpenChange={(open) => { if (!open) setCancelling(null); }}
      title={cancelling ? `Cancel the code for ${cancelling.displayName}?` : "Cancel enrollment code"}
      description="The code stops working immediately. Nothing is removed — the record of the invitation stays in the audit trail. Create a new code to try again."
      confirmLabel="Cancel this code"
      danger
      pending={cancel.isPending}
      error={cancel.error ? errorMessage(cancel.error) : undefined}
      onConfirm={() => { if (cancelling) cancel.mutate(cancelling); }}
    />
  </>;
}
