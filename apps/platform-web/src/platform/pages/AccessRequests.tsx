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
  const refresh = () => platformOnboardingApi("requests").then(setRows);
  useEffect(() => {
    void refresh().catch((e) => setError(e.message));
  }, []);
  return (
    <section>
      <h2>Customer and trial requests</h2>
      <p>
        Customer approval creates an invitation. Assign product access
        separately on the restaurant’s commercial page.
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
              <Link to={`/admin/venues/${row.approvedVenueId}/commercial`}>
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
                  setBusy(true);
                  setError("");
                  setLink("");
                  try {
                    const result = await platformOnboardingApi(
                      `requests/${row.id}/review`,
                      { ...body, status: button.value },
                      "POST",
                    );
                    if (result.prepared?.invitationPath)
                      setLink(
                        new URL(result.prepared.invitationPath, location.origin)
                          .href,
                      );
                    await refresh();
                  } catch (e) {
                    setError((e as Error).message);
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                <fieldset disabled={busy}>
                  {row.requestedVenueId && (
                    <>
                      <label>
                        Approved trial plan
                        <select name="planId" defaultValue="">
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
                        <input name="trialEndsAt" type="date" />
                      </label>
                    </>
                  )}
                  <label>
                    Review note
                    <input name="note" maxLength={1000} />
                  </label>
                  <div className="customer-row">
                    <button value="APPROVED">
                      {row.requestedVenueId
                        ? "Approve trial"
                        : "Approve customer"}
                    </button>
                    <button className="secondary" value="REJECTED">
                      Reject
                    </button>
                  </div>
                </fieldset>
              </form>
            )}
          </article>
        ))
      )}
    </section>
  );
}
