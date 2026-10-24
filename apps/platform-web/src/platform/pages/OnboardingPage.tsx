import { AccessRequests } from "./AccessRequests";
import { ProtectedInstallerDownloads } from "../../customer/ProtectedInstallerDownloads";
import { CustomerOnboarding } from "./CustomerOnboarding";
import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { platformOnboardingApi, platformApi } from "../api";
import { useAuth } from "../auth";
import { PrinterForm } from "../../customer/CustomerDashboard";
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
        <h1>{venueId ? "Restaurant onboarding" : "Customer onboarding"}</h1>
        {!venueId && <ProtectedInstallerDownloads admin readonly={readonly} />}
        {error && <p role="alert">{error}</p>}
        {!venueId && <AccessRequests readonly={readonly} plans={plans} />}
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
              <Link to={`/venues/${venueId}/commercial`}>
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
          <section>
            <h2>Release links and assisted setup</h2>
            <form
              key={data?.updatedAt ?? "new"}
              onSubmit={async (e) => {
                e.preventDefault();
                setBusy(true);
                setError("");
                const f = new FormData(e.currentTarget);
                try {
                  await platformOnboardingApi("policy", {
                    enabled: data.enabled,
                    trialPlanId: data.trialPlanId ?? "",
                    trialDays: data.trialDays,
                    defaultWebsiteMode: data.defaultWebsiteMode,
                    releaseLinks: Object.fromEntries(
                      [
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
                Public signup is a request only. Approvals and product
                assignments are separate operator actions.
              </p>
              <fieldset disabled={readonly || busy || !data}>
                <input type="hidden" name="trialDays" value="14" />
                <input type="hidden" name="defaultWebsiteMode" value="NONE" />
                {[
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
          </section>
        )}
        {!venueId && <CustomerOnboarding plans={plans} readonly={readonly} />}
      </main>
    </div>
  );
}
