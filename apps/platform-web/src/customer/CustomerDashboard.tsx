import { useLocation } from "react-router-dom";
import { useEffect, useState } from "react";
import { customerApi, customerLogout, hasCustomerSession } from "./api";
import { FirstRunSetup } from "./FirstRunSetup";
import { OwnerPortal } from "./OwnerPortal";
import { needsFirstRun, useWebsite } from "./useWebsite";
import type { Portal } from "./portal-types";
import "./customer.css";

export { PrinterForm } from "./OperationsSections";

/**
 * Owner entry point: sign in, then either the three-field first-run setup or
 * the sectioned owner portal. Setup never asks for anything beyond the
 * restaurant name, logo and website address.
 */
export function CustomerPortal() {
  const location = useLocation();
  const [selectedVenue, setSelectedVenue] = useState<string | undefined>(
    location.state?.venueId,
  );
  const [signedIn, setSignedIn] = useState(hasCustomerSession);
  const [signup, setSignup] = useState(true);
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
  const website = useWebsite(venue?.venue.id);
  const inSetup = !!portal && (!venue || needsFirstRun(website.settings));

  useEffect(() => {
    if (!signedIn) return;
    void refresh().catch((e) => setError(e.message));
  }, [signedIn]);
  // Live POS/Manager status for the portal; setup has nothing to poll.
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
    setSignedIn(false);
    setPortal(undefined);
  };

  const shell = (content: React.ReactNode, wide = false) => (
    <div className="customer">
      <header>
        <a href="/ka" className="customer-brand">
          Vynic
        </a>
        <span>{signedIn ? "რესტორნის პორტალი" : "თქვენი რესტორანი"}</span>
        {signedIn && (
          <button className="secondary" onClick={logout}>
            გასვლა
          </button>
        )}
      </header>
      <main className={wide ? "is-wide" : undefined}>
        {error && (
          <p role="alert" className="customer-error">
            {error}
          </p>
        )}
        {content}
      </main>
    </div>
  );

  if (!signedIn)
    return shell(
      <>
        <h1>დაიწყე Vynic-ის გამოყენება</h1>
        <section className="customer-auth">
          <p>ერთი ანგარიში თქვენი რესტორნის დასაკავშირებლად.</p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const form = e.currentTarget;
              const data = Object.fromEntries(new FormData(form));
              void run(async () => {
                await customerApi(`auth/${signup ? "signup" : "login"}`, data);
                form.reset();
                setSignedIn(true);
              });
            }}
          >
            {signup && (
              <label>
                სახელი
                <input
                  name="displayName"
                  required
                  maxLength={100}
                  autoComplete="name"
                />
              </label>
            )}
            <label>
              ელფოსტა
              <input
                name="email"
                type="email"
                required
                maxLength={254}
                autoComplete="email"
              />
            </label>
            <label>
              პაროლი
              <input
                name="password"
                type="password"
                required
                minLength={signup ? 15 : 1}
                maxLength={128}
                autoComplete={signup ? "new-password" : "current-password"}
              />
            </label>
            {signup && (
              <p>
                მინიმუმ 15 სიმბოლო. საცდელ ეტაპზე ელფოსტის დადასტურება და
                პაროლის ავტომატური აღდგენა ჯერ არ არის ხელმისაწვდომი.
              </p>
            )}
            <button disabled={busy}>
              {signup ? "ანგარიშის შექმნა" : "შესვლა"}
            </button>
          </form>
          <button
            className="secondary"
            onClick={() => {
              setSignup(!signup);
              setError("");
            }}
          >
            {signup ? "უკვე გაქვთ ანგარიში? შესვლა" : "ახალი ანგარიშის შექმნა"}
          </button>
        </section>
      </>,
    );
  if (!portal || (venue && !website.loaded))
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
    <OwnerPortal
      key={venue!.venue.id}
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
    true,
  );
}
