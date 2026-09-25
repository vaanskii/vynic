import { publicSiteUrl } from "../../site-origins";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { platformOnboardingApi } from "../api";
import type { Plan } from "../types";
type Request = {
  id: string;
  applicantName: string;
  businessName: string;
  email: string;
  phone: string;
  note: string | null;
  requestedPlanId: string | null;
  requestedVenueId: string | null;
  approvedVenueId: string | null;
  status: string;
  createdAt: string;
  reviewNote: string | null;
};
export function AccessRequests({
  readonly,
  plans,
}: {
  readonly: boolean;
  plans: Plan[];
}) {
  const [rows, setRows] = useState<Request[]>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [link, setLink] = useState("");
  const [minimumTrialDate] = useState(() =>
    new Date(Date.now() + 86400000).toISOString().slice(0, 10),
  );
  const [outcomes, setOutcomes] = useState<Record<string, string>>({});
  const [review, setReview] = useState<{
    row: Request;
    body: Record<string, unknown>;
    summary: string;
  } | null>(null);
  const confirm = async () => {
    if (!review) return;
    setBusy(true);
    setError("");
    setLink("");
    try {
      const result = await platformOnboardingApi(
        `requests/${review.row.id}/review`,
        review.body,
        "POST",
      );
      if (result.prepared?.invitationPath)
        setLink(publicSiteUrl(result.prepared.invitationPath));
      await refresh();
      setReview(null);
    } catch (error) {
      setError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const refresh = () => platformOnboardingApi("requests").then(setRows);
  useEffect(() => {
    void refresh().catch((e) => setError(e.message));
  }, []);
  return (
    <section>
      <h2>Customer and trial requests</h2>
      <p>
        Choose access without a package or start the selected trial when
        approving. The owner receives the approved access after accepting their
        invitation.
      </p>
      {error && <p role="alert">{error}</p>}
      {link && (
        <label>
          Owner invitation — copy and share with the applicant
          <input
            readOnly
            value={link}
            onFocus={(e) => e.currentTarget.select()}
          />
        </label>
      )}
      {!rows ? (
        <p role="status">Loading requests…</p>
      ) : !rows.length ? (
        <p>No requests yet.</p>
      ) : (
        rows.map((row) => (
          <article className="portal-card" key={row.id}>
            <h3>
              {row.businessName} ·{" "}
              {row.requestedVenueId ? "Trial request" : "New customer"}
            </h3>
            <p>
              {row.applicantName} · {row.email} · {row.phone}
            </p>
            <p>
              {row.status} · {new Date(row.createdAt).toLocaleDateString()}
            </p>
            {row.requestedPlanId && (
              <p>
                Requested:{" "}
                {plans.find((p) => p.id === row.requestedPlanId)?.name ??
                  "Retired package"}
              </p>
            )}
            {row.note && <p>{row.note}</p>}
            {row.reviewNote && <p>Review note: {row.reviewNote}</p>}
            {row.approvedVenueId && (
              <Link to={`/venues/${row.approvedVenueId}/commercial`}>
                Manage plan and trial
              </Link>
            )}
            {!readonly && row.status === "PENDING" && (
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  const button = (e.nativeEvent as SubmitEvent)
                    .submitter as HTMLButtonElement;
                  const body = Object.fromEntries(
                    new FormData(e.currentTarget),
                  );
                  const outcome =
                    outcomes[row.id] ??
                    (row.requestedVenueId ? "TRIAL" : "NO_PLAN");
                  const status = button.value;
                  setError("");
                  setReview({
                    row,
                    body: { ...body, outcome, status },
                    summary:
                      status === "REJECTED"
                        ? "The request will be rejected."
                        : outcome === "TRIAL"
                          ? `${plans.find((p) => p.id === body.planId)?.name ?? "Selected plan"} Trial · active until ${body.trialEndsAt}. Product access starts immediately.`
                          : "No active package. The owner can sign in, but paid products remain locked.",
                  });
                }}
              >
                <fieldset disabled={busy}>
                  <label>
                    Approval outcome
                    <select
                      name="outcome"
                      value={
                        outcomes[row.id] ??
                        (row.requestedVenueId ? "TRIAL" : "NO_PLAN")
                      }
                      onChange={(e) =>
                        setOutcomes({ ...outcomes, [row.id]: e.target.value })
                      }
                    >
                      <option value="NO_PLAN">Approve without package</option>
                      <option value="TRIAL">Approve with Trial</option>
                    </select>
                  </label>
                  {(outcomes[row.id] ??
                    (row.requestedVenueId ? "TRIAL" : "NO_PLAN")) ===
                    "TRIAL" && (
                    <>
                      <label>
                        Approved trial plan
                        <select
                          name="planId"
                          required
                          defaultValue={row.requestedPlanId ?? ""}
                        >
                          <option value="">Choose plan</option>
                          {plans
                            .filter((p) => p.status === "ACTIVE")
                            .map((p) => (
                              <option key={p.id} value={p.id}>
                                {p.name}
                              </option>
                            ))}
                        </select>
                      </label>
                      <label>
                        Trial ends
                        <input
                          name="trialEndsAt"
                          type="date"
                          required
                          min={minimumTrialDate}
                        />
                      </label>
                    </>
                  )}
                  <label>
                    Review note
                    <input name="note" maxLength={1000} />
                  </label>
                  <div className="customer-row">
                    <button value="APPROVED">Review approval</button>
                    <button
                      className="secondary"
                      value="REJECTED"
                      formNoValidate
                    >
                      Reject
                    </button>
                  </div>
                </fieldset>
              </form>
            )}
          </article>
        ))
      )}
      <ConfirmDialog
        open={!!review}
        onOpenChange={(open) => {
          if (!open && !busy) setReview(null);
        }}
        title={
          review?.body.status === "REJECTED"
            ? "Reject request?"
            : `Approve ${review?.row.businessName ?? "request"}?`
        }
        description={review?.summary ?? ""}
        confirmLabel="Confirm review"
        pending={busy}
        error={error || undefined}
        onConfirm={() => void confirm()}
      />
    </section>
  );
}
