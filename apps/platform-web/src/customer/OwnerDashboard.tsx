import { useRef, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import {
  dashboardPath,
  dashboardSections,
  type DashboardSection,
} from "./dashboard-routes";
import {
  DevicesSection,
  ManagersSection,
  PaymentsSection,
  SettingsSection,
  SubscriptionSection,
  subscriptionLabels,
} from "./OperationsSections";
import type { IssuedEnrollment, Portal, VenueStatus } from "./portal-types";
import {
  HoursSection,
  MenuSection,
  PhotosSection,
  ProfileSection,
  PublishActions,
  SectionHeader,
  WebsiteSection,
  WebsiteStatus,
} from "./WebsiteSections";
import { websiteAddress, type Website } from "./useWebsite";

/**
 * The owner dashboard after first-run setup. Keyed by restaurant, so switching
 * restaurants starts from a clean dashboard.
 *
 * One section per concern, each at its own /dashboard path (see
 * dashboard-routes). Website sections share one draft and one save bar;
 * operational sections save on their own.
 */
export function OwnerDashboard({
  section,
  portal,
  venue,
  website,
  busy,
  run,
  refresh,
  onError,
  onLogout,
  venueSwitcher,
}: {
  section: DashboardSection;
  portal: Portal;
  venue: VenueStatus;
  website: Website;
  busy: boolean;
  run: (work: () => Promise<unknown>) => Promise<void>;
  refresh: () => Promise<void>;
  onError: (message: string) => void;
  onLogout: () => void;
  venueSwitcher?: ReactNode;
}) {
  const navigate = useNavigate();
  const [enrollment, setEnrollment] = useState<IssuedEnrollment>();
  // Below 900px the sections live behind a burger button in a slide-in panel.
  const [menuOpen, setMenuOpen] = useState(false);
  const burger = useRef<HTMLButtonElement>(null);
  const navRef = useRef<HTMLElement>(null);
  const openMenu = () => {
    setMenuOpen(true);
    requestAnimationFrame(() =>
      navRef.current
        ?.querySelector<HTMLButtonElement>('[aria-current="page"]')
        ?.focus(),
    );
  };
  const closeMenu = () => {
    setMenuOpen(false);
    burger.current?.focus();
  };
  const go = (next: DashboardSection) => {
    navigate(dashboardPath(next));
    setMenuOpen(false);
    window.scrollTo?.({ top: 0 });
  };
  const available = (key: string) => {
    const feature = (
      {
        devices: "POS",
        managers: "MANAGER_APP",
        website: "WEBSITE",
        menu: "WEBSITE",
        hours: "WEBSITE",
        photos: "WEBSITE",
        payments: "ONLINE_PAYMENTS",
      } as Record<string, string>
    )[key];
    return !feature || venue.features.includes(feature);
  };
  const current = dashboardSections.find(([key]) => key === section)![1];

  const common = {
    venue,
    releaseLinks: portal.releaseLinks,
    busy,
    run,
    refresh,
    onError,
  };
  return (
    <div className="portal">
      <aside
        className="portal-sidebar"
        onKeyDown={(e) => {
          if (e.key === "Escape" && menuOpen) closeMenu();
        }}
      >
        <div className="portal-venue">
          <VenueMark website={website} name={venue.venue.name} />
          <div>
            <strong>{venue.venue.name}</strong>
            {website.settings?.mode === "SAAS" && (
              <small>{websiteAddress(website.settings)}</small>
            )}
          </div>
        </div>
        <button
          ref={burger}
          type="button"
          className="portal-burger"
          aria-expanded={menuOpen}
          aria-controls="portal-sections"
          aria-label={`განყოფილებები · ${current}`}
          onClick={() => (menuOpen ? closeMenu() : openMenu())}
        >
          <span className="portal-burger__icon" aria-hidden="true">
            <span />
            <span />
            <span />
          </span>
          <span aria-hidden="true">{current}</span>
        </button>
        {venueSwitcher}
        {menuOpen && (
          <div
            className="portal-backdrop"
            aria-hidden="true"
            onClick={closeMenu}
          />
        )}
        <nav
          id="portal-sections"
          ref={navRef}
          className={menuOpen ? "is-open" : undefined}
          aria-label="მართვის პანელის განყოფილებები"
        >
          <div className="portal-drawer__head">
            <strong>{venue.venue.name}</strong>
            <button
              type="button"
              className="portal-drawer__close"
              aria-label="მენიუს დახურვა"
              onClick={closeMenu}
            >
              ×
            </button>
          </div>
          {dashboardSections
            .filter(([key]) => available(key))
            .map(([key, label]) => (
              <button
                key={key}
                type="button"
                aria-current={section === key ? "page" : undefined}
                onClick={() => go(key)}
              >
                {label}
              </button>
            ))}
        </nav>
      </aside>
      <div className="portal-main">
        {!available(section) && (
          <section className="portal-card">
            <h2>{current}</h2>
            <p>ამ პროდუქტის დასამატებლად განაახლეთ პაკეტი.</p>
            <button onClick={() => go("subscription")}>პაკეტის ნახვა</button>
          </section>
        )}
        {section === "home" && (
          <Dashboard venue={venue} website={website} go={go} />
        )}
        {section === "restaurant" && (
          <ProfileSection
            venue={venue.venue}
            website={website}
            onSaved={refresh}
          />
        )}
        {section === "website" && available(section) && (
          <WebsiteSection
            website={website}
            address={venue.venue.address}
            onEditProfile={() => go("restaurant")}
          />
        )}
        {section === "menu" && available(section) && (
          <MenuSection
            website={website}
            onCatalogSaved={() => void run(refresh)}
          />
        )}
        {section === "photos" && available(section) && (
          <PhotosSection website={website} />
        )}
        {section === "hours" && available(section) && (
          <HoursSection website={website} />
        )}
        {section === "payments" && available(section) && (
          <PaymentsSection venue={venue} />
        )}
        {section === "devices" && available(section) && (
          <DevicesSection
            {...common}
            enrollment={enrollment}
            setEnrollment={setEnrollment}
          />
        )}
        {section === "managers" && available(section) && (
          <ManagersSection {...common} />
        )}
        {section === "subscription" && <SubscriptionSection venue={venue} />}
        {section === "settings" && (
          <SettingsSection
            account={portal.account}
            venue={venue}
            onLogout={onLogout}
          />
        )}
        <SaveBar website={website} />
      </div>
    </div>
  );
}

function VenueMark({ website, name }: { website: Website; name: string }) {
  const logo = website.settings?.draft?.logoUrl;
  const [failed, setFailed] = useState(false);
  if (logo && !failed)
    return (
      <img
        className="portal-venue__logo"
        src={
          logo.startsWith("/media/")
            ? `${(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "")}${logo}`
            : logo
        }
        alt=""
        onError={() => setFailed(true)}
      />
    );
  return (
    <span className="portal-venue__logo" aria-hidden="true">
      {name.slice(0, 1).toUpperCase()}
    </span>
  );
}

/** Unsaved website edits, visible from whichever section they were made in. */
function SaveBar({ website }: { website: Website }) {
  if (!website.dirty && !website.error && !website.message) return null;
  return (
    <div
      className={`portal-savebar${website.dirty ? " is-dirty" : ""}`}
      role="region"
      aria-label="ვებსაიტის ცვლილებები"
    >
      <p role={website.error ? "alert" : "status"}>
        {website.error ||
          (website.dirty ? "შეუნახავი ცვლილებები" : website.message)}
      </p>
      {website.dirty && (
        <div className="customer-row">
          <button
            type="button"
            className="secondary"
            disabled={website.busy}
            onClick={website.discard}
          >
            გაუქმება
          </button>
          <button
            type="button"
            disabled={website.busy}
            onClick={() => void website.save()}
          >
            {website.busy ? "ინახება…" : "შენახვა"}
          </button>
        </div>
      )}
      {!website.dirty && website.error && (
        <button
          type="button"
          className="secondary"
          disabled={website.busy}
          onClick={() => void website.load()}
        >
          განახლება
        </button>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- dashboard

type Step = {
  key: string;
  label: string;
  hint: string;
  done: boolean;
  section: DashboardSection;
  website?: boolean;
};

export function nextSteps(venue: VenueStatus, website: Website): Step[] {
  const draft = website.settings?.draft;
  const saas =
    venue.features.includes("WEBSITE") && website.settings?.mode === "SAAS";
  const steps: Step[] = [
    {
      key: "publish",
      label: "ვებსაიტის ნახვა",
      hint: "ნახეთ საიტი და გამოაქვეყნეთ, როცა მზად იქნებით.",
      done: website.settings?.status === "PUBLISHED",
      section: "website",
      website: true,
    },
    {
      key: "menu",
      label: "მენიუს დამატება",
      hint:
        venue.venue.menuAuthority === "CLOUD"
          ? "დაამატეთ კატეგორიები, კერძები და ფასები."
          : "მენიუ იქმნება POS-ში და ავტომატურად ჩანს საიტზე.",
      done: !!venue.checklist?.menu,
      section: "menu",
    },
    {
      key: "hours",
      label: "სამუშაო საათების დამატება",
      hint: "სტუმრებმა იციან, როდის გეწვიონ.",
      done: !!draft?.workingHours?.length,
      section: "hours",
      website: true,
    },
    {
      key: "address",
      label: "მისამართის დამატება",
      hint: "მისამართი და რუკა გამოჩნდება საიტზე.",
      done: !!venue.venue.address,
      section: "restaurant",
    },
    {
      key: "photos",
      label: "ფოტოების დამატება",
      hint: "მთავარი ფოტო და გალერეა.",
      done: !!(draft?.heroImageUrl || draft?.gallery?.length),
      section: "photos",
      website: true,
    },
    {
      key: "pos",
      label: "POS-ის დაკავშირება",
      hint: "მაგიდები, შეკვეთები და გაყიდვები.",
      done: venue.devices.some((d) => d.status === "ACTIVE"),
      section: "devices",
    },
    {
      key: "manager",
      label: "მენეჯერის დამატება",
      hint: "რესტორნის მართვა ტელეფონიდან.",
      done: !!venue.checklist?.manager,
      section: "managers",
    },
  ];
  return steps.filter(
    (step) =>
      (saas || !step.website) &&
      (step.key !== "menu" || venue.features.includes("WEBSITE")) &&
      (step.key !== "photos" ||
        website.settings?.mediaUploadAllowed === true) &&
      (step.key !== "pos" || venue.features.includes("POS")) &&
      (step.key !== "manager" || venue.features.includes("MANAGER_APP")),
  );
}

function Dashboard({
  venue,
  website,
  go,
}: {
  venue: VenueStatus;
  website: Website;
  go: (section: DashboardSection) => void;
}) {
  const settings = website.settings;
  const steps = nextSteps(venue, website);
  const done = steps.filter((s) => s.done).length;
  const percent = steps.length ? Math.round((done / steps.length) * 100) : 0;
  const sub = venue.subscription;
  if (
    !venue.features.some((f) => ["WEBSITE", "POS", "MANAGER_APP"].includes(f))
  )
    return (
      <>
        <SectionHeader
          title={`გამარჯობა, ${venue.venue.name}`}
          lead="აქტიური პაკეტი ჯერ არ გაქვთ. თქვენი ანგარიში და რესტორნის ინფორმაცია ხელმისაწვდომია."
        />
        <div className="portal-grid">
          {["ვებსაიტი", "POS", "მენეჯერის აპლიკაცია"].map((name) => (
            <section key={name} className="portal-card">
              <h3>{name}</h3>
              <p>არ არის ჩართული</p>
              <button onClick={() => go("subscription")}>
                დაუკავშირდით Vynic-ს
              </button>
            </section>
          ))}
        </div>
      </>
    );
  return (
    <>
      <SectionHeader
        title={`გამარჯობა, ${venue.venue.name}`}
        lead="თქვენი რესტორანი მზადაა. ქვემოთ — შემდეგი ნაბიჯები, როცა მოიცლით."
      />
      <div className="portal-overview">
        <section className="portal-card portal-card--website">
          <h3>ვებსაიტი</h3>
          {venue.features.includes("WEBSITE") && settings?.mode === "SAAS" ? (
            <>
              <p className="portal-address">{websiteAddress(settings)}</p>
              <WebsiteStatus website={website} />
              {!settings.entitled && (
                <p className="portal-hint">
                  გამოქვეყნება თქვენს პაკეტში გამორთულია.
                </p>
              )}
              <PublishActions website={website} />
            </>
          ) : settings ? (
            <p className="portal-hint">
              {settings.mode === "CUSTOM"
                ? "ინდივიდუალური ვებსაიტი ცალკე იმართება."
                : "ვებსაიტი თქვენს პაკეტში ჯერ არ არის ჩართული."}
            </p>
          ) : (
            <p>ვებსაიტი არ არის ჩართული.</p>
          )}
        </section>
        <section className="portal-card">
          <h3>პაკეტი</h3>
          <p className="portal-stat">{venue.plan?.name ?? "—"}</p>
          <p>
            {subscriptionLabels[sub?.status ?? "NO_PLAN"] ?? sub?.status}
            {sub?.trialEndsAt &&
              ` · ${new Date(sub.trialEndsAt).toLocaleDateString("ka-GE")}-მდე`}
          </p>
          <button
            type="button"
            className="portal-link"
            onClick={() => go("subscription")}
          >
            დეტალები
          </button>
        </section>
        <section className="portal-card">
          <h3>გამართვის პროგრესი</h3>
          <p className="portal-stat">
            {done} / {steps.length}
          </p>
          <div
            className="portal-progress"
            role="progressbar"
            aria-label="გამართვის პროგრესი"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={percent}
          >
            <span style={{ width: `${percent}%` }} />
          </div>
        </section>
      </div>
      <section className="portal-card">
        <h3>შემდეგი ნაბიჯები</h3>
        <p className="portal-hint">
          ყველა არასავალდებულოა — დაამატეთ, როცა მოგიხერხდებათ.
        </p>
        <ul className="portal-steps" aria-label="შემდეგი ნაბიჯები">
          {steps.map((step) => (
            <li key={step.key} className={step.done ? "is-done" : undefined}>
              <span className="portal-steps__mark" aria-hidden="true">
                {step.done ? "✓" : ""}
              </span>
              <div>
                <strong>{step.label}</strong>
                <small>{step.done ? "დასრულებულია" : step.hint}</small>
              </div>
              <button
                type="button"
                className="secondary"
                aria-label={`${step.done ? "ნახვა" : "დაწყება"}: ${step.label}`}
                onClick={() => go(step.section)}
              >
                {step.done ? "ნახვა" : "დაწყება"}
              </button>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
