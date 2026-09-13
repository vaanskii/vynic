import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { platformOnboardingApi, platformApi } from "../api";
import { useAuth } from "../auth";
import { PrinterForm } from "../../customer/CustomerPortal";
export function OnboardingPage() {
  const { venueId } = useParams();
  const auth = useAuth();
  const [data, setData] = useState<any>();
  const [plans, setPlans] = useState<any[]>([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const readonly = auth.actor?.role === "SUPPORT_READONLY";
  const refresh = async () => {
    setData(
      await platformOnboardingApi(venueId ? `venues/${venueId}` : "policy"),
    );
  };
  useEffect(() => {
    void refresh().catch((e) => setError(e.message));
    if (!venueId)
      void platformApi
        .plans()
        .then((p) => setPlans(p))
        .catch((e) => setError(e.message));
  }, [venueId]);
  return (
    <div className="customer">
      <main>
        <h1>{venueId ? "Restaurant onboarding" : "Pilot onboarding policy"}</h1>
        {error && <p role="alert">{error}</p>}
        {venueId ? (
          data && (
            <>
              <p>
                {data.venue.name} · {data.venue.loginCode} ·{" "}
                {data.subscription?.status}
              </p>
              <p>
                {data.organization.accounts
                  .map(
                    (a: any) =>
                      `${a.displayName} · ${a.email} · ${a.emailVerifiedAt ? "verified" : "unverified"}`,
                  )
                  .join(", ") || "No customer owner attached"}
              </p>
              <ul>
                {Object.entries(data.checklist).map(([k, v]) => (
                  <li key={k}>
                    {v ? "✓" : "○"} {k}
                  </li>
                ))}
              </ul>
              <Link to={`/admin/venues/${venueId}/commercial`}>
                Manager and subscription controls
              </Link>
              {data.devices.map((d: any) => (
                <section key={d.id}>
                  <h2>{d.displayName}</h2>
                  <p>
                    {d.status} · {d.lastSeenAt ?? "Never seen"}
                  </p>
                  {readonly ? (
                    <p>
                      Printer configuration:{" "}
                      {d.runtimeConfig ? "Configured" : "Not configured"}
                    </p>
                  ) : (
                    <PrinterForm
                      initial={d.runtimeConfig}
                      save={(body) =>
                        platformOnboardingApi(
                          `venues/${venueId}/devices/${d.id}/printers`,
                          body,
                        )
                      }
                    />
                  )}
                </section>
              ))}
            </>
          )
        ) : (
          <form
            key={data?.updatedAt ?? "new"}
            onSubmit={async (e) => {
              e.preventDefault();
              setBusy(true);
              setError("");
              const f = new FormData(e.currentTarget);
              try {
                await platformOnboardingApi("policy", {
                  enabled: f.get("enabled") === "on",
                  trialPlanId: f.get("trialPlanId"),
                  trialDays: Number(f.get("trialDays")),
                  releaseLinks: Object.fromEntries(
                    [
                      "posWindows",
                      "managerWindows",
                      "managerMacos",
                      "managerAndroid",
                      "managerIos",
                    ].map((k) => [k, f.get(k)]),
                  ),
                });
                await refresh();
              } catch (e) {
                setError((e as Error).message);
              } finally {
                setBusy(false);
              }
            }}
          >
            <p>
              Registration stays closed until an active trial plan is selected.
              Email verification and automatic password recovery are not
              available in this pilot.
            </p>
            <fieldset disabled={readonly || busy}>
              <label>
                <input
                  name="enabled"
                  type="checkbox"
                  defaultChecked={data?.enabled}
                />{" "}
                Open pilot registration
              </label>
              <label>
                Trial plan
                <select
                  name="trialPlanId"
                  defaultValue={data?.trialPlanId ?? ""}
                >
                  <option value="">Choose plan</option>
                  {plans.map((p) => (
                    <option value={p.id} key={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Trial days
                <input
                  type="number"
                  name="trialDays"
                  min={1}
                  max={90}
                  defaultValue={data?.trialDays ?? 14}
                  required
                />
              </label>
              {[
                "posWindows",
                "managerWindows",
                "managerMacos",
                "managerAndroid",
                "managerIos",
              ].map((k) => (
                <label key={k}>
                  {k} release URL
                  <input
                    type="url"
                    name={k}
                    defaultValue={data?.releaseLinks?.[k] ?? ""}
                    placeholder="HTTPS release link, when published"
                  />
                </label>
              ))}
              {!readonly && <button>Save policy</button>}
            </fieldset>
          </form>
        )}
      </main>
    </div>
  );
}
