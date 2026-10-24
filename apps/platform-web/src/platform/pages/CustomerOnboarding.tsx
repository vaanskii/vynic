import { publicSiteUrl } from "../../site-origins";
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { platformOnboardingApi } from "../api";
import {
  WebsiteModeField,
  planHasWebsite,
} from "../components/WebsiteModeField";
type Plan = {
  id: string;
  name: string;
  status?: string;
  features?: Array<{ feature: { key: string; name: string } }>;
};
type Organization = {
  id: string;
  name: string;
  venues: { id: string; name: string }[];
};
type Invitation = {
  id: string;
  organization: { name: string };
  email: string;
  expiresAt: string;
  acceptedAt: string | null;
  revokedAt: string | null;
  recoveryRequestedAt?: string | null;
};
export function CustomerOnboarding({
  plans,
  readonly,
}: {
  plans: Plan[];
  readonly: boolean;
}) {
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [prepared, setPrepared] = useState({
    planId: "",
    status: "NO_PLAN",
    websiteMode: "",
  });
  const [invitations, setInvitations] = useState<Invitation[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [link, setLink] = useState("");
  const [message, setMessage] = useState("");
  async function refresh() {
    const [orgs, invites] = await Promise.all([
      platformOnboardingApi("organizations"),
      platformOnboardingApi("invitations"),
    ]);
    setOrganizations(orgs);
    setInvitations(invites);
    setLoading(false);
  }
  useEffect(() => {
    let active = true;
    Promise.all([
      platformOnboardingApi("organizations"),
      platformOnboardingApi("invitations"),
    ])
      .then(([orgs, invites]) => {
        if (active) {
          setOrganizations(orgs);
          setInvitations(invites);
          setLoading(false);
        }
      })
      .catch((e) => {
        if (active) {
          setError(e.message);
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, []);
  async function run(path: string, body: unknown) {
    setBusy(true);
    setError("");
    setMessage("");
    setLink("");
    try {
      const result = await platformOnboardingApi(path, body, "POST");
      if (result.invitationPath) setLink(publicSiteUrl(result.invitationPath));
      else setMessage("Invitation revoked.");
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <section>
        <h2>Customer / Organization onboarding</h2>
        <p>
          Prepare the restaurant, then send its owner an invitation. The owner
          chooses their own password.
        </p>
        {error && <p role="alert">{error}</p>}
        {message && <p role="status">{message}</p>}
        {link && (
          <div className="invitation-result">
            <label>
              Owner invitation link
              <input
                readOnly
                value={link}
                onFocus={(e) => e.currentTarget.select()}
              />
            </label>
            <button
              type="button"
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(link);
                  setMessage("Invitation link copied.");
                } catch {
                  setError(
                    "Copy failed. Select the link and copy it manually.",
                  );
                }
              }}
            >
              Copy invitation link
            </button>
            <p>
              This link is shown once. It expires in 7 days. Regenerating
              replaces the previous link.
            </p>
          </div>
        )}
        {!readonly && (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const fields = Object.fromEntries(new FormData(e.currentTarget));
              void run("customers", {
                ...fields,
                trialDays: Number(fields.trialDays),
              });
            }}
          >
            <fieldset disabled={busy}>
              <label>
                Organization name
                <input name="organizationName" required maxLength={100} />
              </label>
              <label>
                Restaurant name
                <input name="name" required maxLength={100} />
              </label>
              <label>
                Owner email
                <input name="email" type="email" required maxLength={254} />
              </label>
              <label>
                Plan
                <select
                  name="planId"
                  value={prepared.planId}
                  onChange={(e) =>
                    setPrepared({ ...prepared, planId: e.target.value })
                  }
                >
                  <option value="">No plan</option>
                  {plans
                    .filter(
                      (p) => p.status === undefined || p.status === "ACTIVE",
                    )
                    .map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                </select>
              </label>
              <label>
                Subscription
                <select
                  name="subscriptionStatus"
                  value={prepared.status}
                  onChange={(e) =>
                    setPrepared({ ...prepared, status: e.target.value })
                  }
                >
                  <option value="NO_PLAN">No plan — account only</option>
                  <option value="TRIAL">Trial</option>
                  <option value="ACTIVE">Active</option>
                </select>
              </label>
              {prepared.status !== "NO_PLAN" &&
                planHasWebsite(plans.find((p) => p.id === prepared.planId)) && (
                  <WebsiteModeField
                    value={prepared.websiteMode}
                    onChange={(websiteMode) =>
                      setPrepared({ ...prepared, websiteMode })
                    }
                  />
                )}
              <label>
                Trial days
                <input
                  name="trialDays"
                  type="number"
                  min={1}
                  max={90}
                  defaultValue={14}
                  required
                />
              </label>
              <button>
                {busy ? "Preparing…" : "Create restaurant and invitation"}
              </button>
            </fieldset>
          </form>
        )}
        {organizations.length > 0 && (
          <details>
            <summary>Invite an owner to an existing Organization</summary>
            {!readonly && (
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  void run(
                    "invitations",
                    Object.fromEntries(new FormData(e.currentTarget)),
                  );
                }}
              >
                <fieldset disabled={busy}>
                  <label>
                    Organization
                    <select name="organizationId" required>
                      {organizations.map((o) => (
                        <option value={o.id} key={o.id}>
                          {o.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Owner email
                    <input name="email" type="email" required maxLength={254} />
                  </label>
                  <button>Create invitation</button>
                </fieldset>
              </form>
            )}
            <ul>
              {organizations.map((o) => (
                <li key={o.id}>
                  {o.name}
                  {o.venues.map((v) => (
                    <span key={v.id}>
                      {" "}
                      ·{" "}
                      <Link to={`/venues/${v.id}/commercial`}>
                        {v.name} — plan and features
                      </Link>{" "}
                      ·{" "}
                      <Link to={`/venues/${v.id}/website`}>Website setup</Link>
                    </span>
                  ))}
                </li>
              ))}
            </ul>
          </details>
        )}
      </section>
      <section>
        <h2>Owner invitations</h2>
        {loading ? (
          <p role="status">Loading invitations…</p>
        ) : invitations.length === 0 ? (
          <p>No owner invitations yet.</p>
        ) : (
          <ul className="owner-invitations">
            {invitations.map((i) => {
              const state = i.acceptedAt
                ? "Accepted"
                : i.revokedAt
                  ? "Revoked"
                  : new Date(i.expiresAt) <= new Date()
                    ? "Expired"
                    : "Pending";
              return (
                <li key={i.id}>
                  <strong>{i.organization.name}</strong>
                  <p>
                    {i.email} · {state}
                  </p>
                  <p>Expires {new Date(i.expiresAt).toLocaleString()}</p>
                  {i.recoveryRequestedAt && (
                    <p role="status">
                      New link requested ·{" "}
                      {new Date(i.recoveryRequestedAt).toLocaleString()}
                    </p>
                  )}
                  {!readonly && !i.acceptedAt && (
                    <div className="customer-row">
                      <button
                        className="secondary"
                        disabled={busy}
                        onClick={() => {
                          if (
                            confirm(
                              "Replace this invitation with a new link? The previous link will stop working.",
                            )
                          )
                            void run(`invitations/${i.id}/regenerate`, {});
                        }}
                      >
                        Regenerate link
                      </button>
                      {!i.revokedAt && (
                        <button
                          className="secondary"
                          disabled={busy}
                          onClick={() => {
                            if (confirm("Revoke this invitation?"))
                              void run(`invitations/${i.id}/revoke`, {});
                          }}
                        >
                          Revoke
                        </button>
                      )}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </>
  );
}
