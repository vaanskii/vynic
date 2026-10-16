import { WebsitePaymentReviews } from "./WebsitePaymentReviews";
export { SubscriptionSection } from "./SubscriptionSection";
import { useState } from "react";
import { customerApi } from "./api";
import { PaymentSettings } from "./PaymentSettings";
import { SectionHeader } from "./WebsiteSections";
import type {
  IssuedEnrollment,
  Portal,
  PrinterSettings,
  RuntimeConfig,
  VenueStatus,
} from "./portal-types";

/**
 * Dashboard sections for running the restaurant: POS devices, Manager access,
 * payments, subscription and account settings. Each is independent and
 * optional; none of them blocks the rest of the portal.
 */
type Run = (work: () => Promise<unknown>) => Promise<void>;

type Printer = PrinterSettings;
export function PrinterForm({
  initial,
  save,
}: {
  initial?: RuntimeConfig;
  save: (body: { kitchen: Printer; receipt: Printer }) => Promise<unknown>;
}) {
  const [printers, setPrinters] = useState<{
    kitchen: Printer;
    receipt: Printer;
  }>(
    initial?.printers ?? {
      kitchen: { host: "", port: 9100, enabled: true },
      receipt: { host: "", port: 9100, enabled: true },
    },
  );
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        setMessage("");
        try {
          await save(printers);
          setMessage("შენახულია. POS მიიღებს პარამეტრებს დაკავშირებისას.");
        } catch (e) {
          setMessage((e as Error).message);
        } finally {
          setBusy(false);
        }
      }}
    >
      <div className="customer-columns">
        {(["kitchen", "receipt"] as const).map((key) => (
          <fieldset key={key}>
            <legend>
              {key === "kitchen" ? "სამზარეულოს პრინტერი" : "ქვითრის პრინტერი"}
            </legend>
            <label>
              <input
                type="checkbox"
                checked={printers[key].enabled}
                onChange={(e) =>
                  setPrinters({
                    ...printers,
                    [key]: { ...printers[key], enabled: e.target.checked },
                  })
                }
              />{" "}
              ჩართული
            </label>
            <label>
              IP / ჰოსტი
              <input
                required={printers[key].enabled}
                value={printers[key].host}
                onChange={(e) =>
                  setPrinters({
                    ...printers,
                    [key]: { ...printers[key], host: e.target.value },
                  })
                }
              />
            </label>
            <label>
              პორტი
              <input
                type="number"
                min="1"
                max="65535"
                required
                value={printers[key].port}
                onChange={(e) =>
                  setPrinters({
                    ...printers,
                    [key]: { ...printers[key], port: Number(e.target.value) },
                  })
                }
              />
            </label>
          </fieldset>
        ))}
      </div>
      <button disabled={busy}>პრინტერების შენახვა</button>
      <p role="status">{message}</p>
    </form>
  );
}

async function copy(value: string, onError: (message: string) => void) {
  try {
    await navigator.clipboard.writeText(value);
  } catch {
    onError("კოპირება ვერ მოხერხდა. მონიშნეთ კოდი და დააკოპირეთ.");
  }
}
const downloads: Record<string, string> = {
  posWindows: "Vynic POS · Windows",
  managerWindows: "Vynic Manager · Windows",
  managerMacos: "Vynic Manager · macOS",
  managerAndroid: "Vynic Manager · Android",
  managerIos: "Vynic Manager · iOS",
};
function Downloads({
  links,
  keys,
}: {
  links: Record<string, string>;
  keys: string[];
}) {
  return (
    <ul className="portal-downloads">
      {keys.map((key) => (
        <li key={key}>
          {links[key] ? (
            <a href={links[key]}>{downloads[key]}</a>
          ) : (
            `${downloads[key]} — ინსტალაციის ბმული ჯერ არ გამოქვეყნებულა`
          )}
        </li>
      ))}
    </ul>
  );
}

// ---------------------------------------------------------------- devices

export function DevicesSection({
  venue,
  releaseLinks,
  busy,
  run,
  refresh,
  onError,
  enrollment,
  setEnrollment,
}: {
  venue: VenueStatus;
  releaseLinks: Record<string, string>;
  busy: boolean;
  run: Run;
  refresh: () => Promise<void>;
  onError: (message: string) => void;
  /** Kept by the dashboard so a fresh code survives switching sections. */
  enrollment?: IssuedEnrollment;
  setEnrollment: (enrollment: IssuedEnrollment) => void;
}) {
  const id = venue.venue.id;
  const [managerSetupChoice, setManagerSetupChoice] = useState({ venueId: id, include: true });
  const initialManagerSetup = venue.initialManagerSetupEligible === true &&
    (managerSetupChoice.venueId !== id || managerSetupChoice.include);
  const current =
    enrollment &&
    venue.enrollments.some(
      (e) => e.id === enrollment.id && e.status === "PENDING",
    )
      ? enrollment
      : undefined;
  return (
    <>
      <SectionHeader
        title="მოწყობილობები / POS"
        lead="Vynic POS მუშაობს რესტორნის Windows კომპიუტერზე, ინტერნეტის გარეშეც."
      />
      <div className="portal-grid">
        <section className="portal-card">
          <h3>1. ჩამოტვირთეთ POS</h3>
          <Downloads links={releaseLinks} keys={["posWindows"]} />
          <h3>2. დააკავშირეთ კოდით</h3>
          <p>გახსენით POS და შეიყვანეთ მოწყობილობის კოდი.</p>
          {venue.initialManagerSetupEligible ? <>
            <label>
              <input type="checkbox" checked={initialManagerSetup} disabled={busy}
                onChange={(event) => setManagerSetupChoice({ venueId: id, include: event.target.checked })} />
              პირველი Manager-ის რეგისტრაციაც
            </label>
            <p>ეს ერთი კოდი რესტორანსაც დააკავშირებს და პირველ Manager-ს სახელისა და PIN-ის არჩევის საშუალებას მისცემს. დამატებითი POS-ისთვის გამორთეთ ეს არჩევანი.</p>
          </> : null}
          {current && (
            <div className="portal-inset">
              <p className="customer-code">{current.code}</p>
              <p>ვადა: {new Date(current.expiresAt).toLocaleString("ka-GE")}</p>
              <button
                className="secondary"
                onClick={() => void copy(current.code, onError)}
              >
                კოდის კოპირება
              </button>
            </div>
          )}
          <button
            disabled={busy}
            onClick={() =>
              void run(async () => {
                if (current)
                  await customerApi(
                    `venues/${id}/enrollments/${current.id}/cancel`,
                    {},
                  );
                setEnrollment(
                  await customerApi<IssuedEnrollment>(
                    `venues/${id}/enrollments`,
                    { initialManagerSetup },
                  ),
                );
                await refresh();
              })
            }
          >
            {current ? "ახალი კოდის შექმნა" : "მოწყობილობის კოდის შექმნა"}
          </button>
          {venue.enrollments
            .filter((e) => e.status === "PENDING" && e.id !== current?.id)
            .map((e) => (
              <button
                className="secondary"
                key={e.id}
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await customerApi(
                      `venues/${id}/enrollments/${e.id}/cancel`,
                      {},
                    );
                    await refresh();
                  })
                }
              >
                კოდის გაუქმება · {e.codeSelector}
              </button>
            ))}
        </section>
        <section className="portal-card">
          <h3>დაკავშირებული მოწყობილობები</h3>
          {!venue.devices.length && (
            <p className="portal-hint">
              ჯერ არცერთი POS არ არის დაკავშირებული.
            </p>
          )}
          {!venue.venue.activeOperationalDeviceId &&
            venue.devices.length > 0 && (
              <p role="status">მთავარი POS არ არის არჩეული.</p>
            )}
          <ul className="portal-list">
            {venue.devices.map((d) => (
              <li key={d.id}>
                <strong>{d.displayName}</strong>
                <span>
                  {d.isOperationalPrimary
                    ? "მთავარი POS"
                    : "მეორადი — ოპერაციების სინქრონიზაცია გამორთულია"}{" "}
                  · {d.status}
                </span>
                <small>
                  {d.lastSeenAt
                    ? `ბოლო კავშირი: ${new Date(d.lastSeenAt).toLocaleString("ka-GE")}`
                    : "კავშირის მოლოდინში"}
                </small>
              </li>
            ))}
          </ul>
          <p className="portal-hint">
            რამდენიმე POS-ის ერთობლივი მუშაობა ჯერ ჩართული არ არის. მხოლოდ
            მთავარი POS აგზავნის რესტორნის ოპერაციებს. მთავარი POS-ის
            შესაცვლელად მიმართეთ Vynic-ის მხარდაჭერას.
          </p>
        </section>
      </div>
      <section className="portal-card">
        <h3>პრინტერები</h3>
        <p>
          შეიყვანეთ რესტორნის ქსელში არსებული პრინტერების მისამართები.
          პარამეტრების მიღების შემდეგ POS ბეჭდავს ინტერნეტის გარეშეც.
        </p>
        {!venue.devices.length && <p>ჯერ დააკავშირეთ POS.</p>}
        {venue.devices.map((d) => (
          <div key={d.id}>
            <h4>{d.displayName}</h4>
            <PrinterForm
              initial={d.runtimeConfig}
              save={async (body) => {
                await customerApi(
                  `venues/${id}/devices/${d.id}/printers`,
                  body,
                  "PUT",
                );
                await refresh();
              }}
            />
          </div>
        ))}
      </section>
    </>
  );
}

// ---------------------------------------------------------------- managers

export function ManagersSection({
  venue,
  releaseLinks,
}: {
  venue: VenueStatus;
  releaseLinks: Record<string, string>;
  busy: boolean;
  run: Run;
  refresh: () => Promise<void>;
  onError: (message: string) => void;
}) {
  return (
    <>
      <SectionHeader
        title="მენეჯერები"
        lead="მენეჯერი რესტორანს მართავს Vynic Manager აპით — ტელეფონიდან ან კომპიუტერიდან."
      />
      <div className="portal-grid">
        <section className="portal-card">
          <h3>Manager აპის დაკავშირება</h3>
          <p className="portal-hint">ახალი მოწყობილობისთვის Vynic-ის მხარდაჭერისგან მიიღეთ ერთჯერადი დაკავშირების კოდი. ერთხელ დაკავშირების შემდეგ შესვლისთვის პირადი PIN გამოიყენეთ.</p>
          <Downloads
            links={releaseLinks}
            keys={[
              "managerWindows",
              "managerMacos",
              "managerAndroid",
              "managerIos",
            ]}
          />
        </section>
        <section className="portal-card">
          <h3>{venue.managers.length ? "მენეჯერები" : "პირველი აქტივაცია"}</h3>
          <ul className="portal-list">
            {venue.managers.map((m) => (
              <li key={m.id}>
                <strong>{m.displayName || m.username}</strong>
                <span>{m.isActive ? "აქტიური" : "გამორთული"}</span>
              </li>
            ))}
          </ul>
          {venue.managers.length ? (
            <p>
              შესვლის შემდეგ თანამშრომლებს მართავთ აპლიკაციიდან. საწყისი
              Manager-ის PIN-ის აღსადგენად დაუკავშირდით Vynic Platform Admin-ს.
            </p>
          ) : venue.features.includes("MANAGER_APP") &&
            venue.features.includes("POS") ? (
            <p>
              მიიღეთ პირველი POS-ის დაკავშირების კოდი „მოწყობილობები / POS“ სექციიდან.
              POS-ში აირჩიეთ სახელი და პირადი PIN — დამატებითი აქტივაციის კოდი აღარ გჭირდებათ.
              შემდეგ Manager აპისთვის Vynic-ის მხარდაჭერისგან მიიღეთ ერთჯერადი დაკავშირების კოდი და შედით თქვენი PIN-ით.
            </p>
          ) : (
            <p>
              პირველი რეგისტრაციისთვის საჭიროა POS-ისა და Manager-ის პაკეტი.
            </p>
          )}
        </section>
      </div>
    </>
  );
}

// ---------------------------------------------------------------- payments

export function PaymentsSection({ venue }: { venue: VenueStatus }) {
  return (
    <>
      <WebsitePaymentReviews key={venue.venue.id} venueId={venue.venue.id} />
      <SectionHeader
        title="ონლაინ გადახდები"
        lead="სტუმრებს შეეძლებათ ვებსაიტზე ჯავშნის ან შეკვეთის გადახდა ბარათით."
      />
      {venue.features.includes("ONLINE_PAYMENTS") ? (
        <PaymentSettings key={venue.venue.id} venueId={venue.venue.id} />
      ) : (
        <div className="portal-empty">
          <strong>ონლაინ გადახდები თქვენს პაკეტში არ შედის</strong>
          <p>ჩასართავად დაუკავშირდით Vynic-ს.</p>
        </div>
      )}
    </>
  );
}

// ---------------------------------------------------------------- subscription

export const subscriptionLabels: Record<string, string> = {
  NO_PLAN: "აქტიური პაკეტი არ გაქვთ",
  LEGACY: "არსებული მომსახურება",
  TRIAL: "საცდელი პერიოდი",
  ACTIVE: "აქტიური",
  PAST_DUE: "გადახდა დაგვიანებულია",
  SUSPENDED: "შეჩერებული",
  CANCELLED: "გაუქმებული",
};
// ---------------------------------------------------------------- settings

export function SettingsSection({
  account,
  venue,
  onLogout,
}: {
  account: Portal["account"];
  venue: VenueStatus;
  onLogout: () => void;
}) {
  return (
    <>
      <SectionHeader title="პარამეტრები" />
      <div className="portal-grid">
        <section className="portal-card">
          <h3>ანგარიში</h3>
          {account.displayName && <p>{account.displayName}</p>}
          <p>
            {account.email}{" "}
            {!account.emailVerifiedAt && (
              <span className="portal-pill portal-pill--draft">
                დაუდასტურებელი
              </span>
            )}
          </p>
          <button className="secondary" onClick={onLogout}>
            გასვლა
          </button>
        </section>
        <section className="portal-card">
          <h3>რესტორანი</h3>
          <dl className="portal-facts">
            <dt>დროის სარტყელი</dt>
            <dd>{venue.venue.timezone}</dd>
            <dt>ვალუტა</dt>
            <dd>{venue.venue.currency}</dd>
          </dl>
        </section>
      </div>
    </>
  );
}
