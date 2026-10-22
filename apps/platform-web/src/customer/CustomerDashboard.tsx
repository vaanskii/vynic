import {
  Link,
  Navigate,
  useLocation,
  useNavigate,
  useParams,
} from "react-router-dom";
import { useEffect, useState } from "react";
import vynicLogo from "../assets/vynic-logo.png";
import { LocaleProvider } from "../lib/i18n";
import { customerApi, customerLogout, hasCustomerSession } from "./api";
import { isDashboardSection } from "./dashboard-routes";
import { FirstRunSetup } from "./FirstRunSetup";
import { OwnerDashboard } from "./OwnerDashboard";
import { needsFirstRun, useWebsite } from "./useWebsite";
import type { Portal } from "./portal-types";
import "./customer.css";

export { PrinterForm } from "./OperationsSections";

/**
 * The signed-in owner area at /dashboard/*: either the three-field first-run
 * setup or the sectioned dashboard. Only a customer account session opens it;
 * without one the owner is sent to /login and brought back afterwards.
 */
export function CustomerDashboard() {
  const location = useLocation();
  const navigate = useNavigate();
  const { section = "home" } = useParams();
  const [selectedVenue, setSelectedVenue] = useState<string | undefined>(
    location.state?.venueId,
  );
  const [signedIn, setSignedIn] = useState(hasCustomerSession);
  const [portal, setPortal] = useState<Portal>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const refresh = async () => {
    try {
      setPortal(await customerApi<Portal>("portal"));
    } catch (error) {
      if (!hasCustomerSession()) {
        setSignedIn(false);
        setPortal(undefined);
      }
      throw error;
    }
  };
  const venue =
    portal?.venues.find((v) => v.venue.id === selectedVenue) ??
    portal?.venues[0];
  const hasWebsite = !!venue?.features.includes("WEBSITE");
  const website = useWebsite(hasWebsite ? venue?.venue.id : undefined);
  const inSetup =
    !!portal && (!venue || (hasWebsite && needsFirstRun(website.settings)));

  useEffect(() => {
    if (!signedIn) return;
    void refresh().catch((e) => setError(e.message));
  }, [signedIn]);
  // Live POS/Manager status for the dashboard; setup has nothing to poll.
  useEffect(() => {
    if (!signedIn || inSetup) return;
    const timer = setInterval(
      () => void refresh().catch((e) => setError(e.message)),
      15000,
    );
    return () => clearInterval(timer);
  }, [signedIn, inSetup]);

  async function run(work: () => Promise<unknown>) {
    setBusy(true);
    setError("");
    try {
      await work();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const logout = () => {
    customerLogout();
    navigate("/", { replace: true });
  };

  if (!signedIn)
    return (
      <Navigate
        to="/login"
        replace
        state={{ from: `${location.pathname}${location.search}` }}
      />
    );
  if (!isDashboardSection(section)) return <Navigate to="/dashboard" replace />;

  const shell = (content: React.ReactNode) => (
    <LocaleProvider locale="ka" title="მართვის პანელი | Vynic">
      <div className="customer dashboard">
        <header className="dashboard-header">
          <Link
            to="/"
            className="dashboard-brand"
            aria-label="Vynic-ის მთავარი გვერდი"
          >
            <img src={vynicLogo} alt="" />
            <span>Vynic</span>
          </Link>
          <span className="dashboard-title">მართვის პანელი</span>
          <div className="dashboard-account">
            {portal && (
              <span className="dashboard-account__name">
                {portal.account.displayName || portal.account.email}
              </span>
            )}
            <button type="button" className="secondary" onClick={logout}>
              გასვლა
            </button>
          </div>
        </header>
        <main className={inSetup || !portal ? undefined : "is-wide"}>
          {error && (
            <p role="alert" className="customer-error">
              {error}
            </p>
          )}
          {content}
        </main>
      </div>
    </LocaleProvider>
  );

  if (!portal || (venue && hasWebsite && !website.loaded))
    return shell(<p role="status">იტვირთება…</p>);
  if (inSetup)
    return shell(
      <FirstRunSetup
        venue={venue?.venue}
        website={website.settings}
        baseDomain={portal.websiteBaseDomain ?? website.settings?.baseDomain}
        onComplete={async () => {
          await refresh();
          await website.load();
        }}
      />,
    );
  return shell(
    <OwnerDashboard
      key={venue!.venue.id}
      section={section}
      portal={portal}
      venue={venue!}
      website={website}
      busy={busy}
      run={run}
      refresh={refresh}
      onError={setError}
      onLogout={logout}
      venueSwitcher={
        portal.venues.length > 1 && (
          <label className="portal-switcher">
            რესტორანი
            <select
              value={venue!.venue.id}
              onChange={(e) => setSelectedVenue(e.target.value)}
            >
              {portal.venues.map((v) => (
                <option key={v.venue.id} value={v.venue.id}>
                  {v.organization?.name} · {v.venue.name}
                </option>
              ))}
            </select>
          </label>
        )
      }
    />,
  );
}
