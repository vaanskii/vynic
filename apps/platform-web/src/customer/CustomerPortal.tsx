import { useEffect, useState } from "react";
import { customerApi, customerLogout, hasCustomerSession } from "./api";
import "./customer.css";

type Printer = { host: string; port: number; enabled: boolean };
export function PrinterForm({
  initial,
  save,
}: {
  initial?: any;
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
const checks: Record<string, string> = {
  restaurant: "რესტორანი შექმნილია",
  manager: "მენეჯერი შექმნილია",
  code: "რესტორნის კოდი მზადაა",
  enrollment: "POS კოდი შექმნილია",
  connected: "POS დაკავშირებულია",
  printers: "პრინტერების პარამეტრები შენახულია",
  menu: "მენიუ შექმნილია POS-ზე",
  tables: "მაგიდები შექმნილია POS-ზე",
  firstSale: "პირველი გაყიდვა მიღებულია",
};
const downloads: Record<string, string> = {
  posWindows: "Vynic POS · Windows",
  managerWindows: "Vynic Manager · Windows",
  managerMacos: "Vynic Manager · macOS",
  managerAndroid: "Vynic Manager · Android",
  managerIos: "Vynic Manager · iOS",
};
export function CustomerPortal() {
  const [signedIn, setSignedIn] = useState(hasCustomerSession);
  const [signup, setSignup] = useState(true);
  const [portal, setPortal] = useState<any>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [enrollment, setEnrollment] = useState<any>();
  const [step, setStep] = useState("manager");
  const [requestId, setRequestId] = useState(crypto.randomUUID());
  const [resetId, setResetId] = useState<string>();
  const refresh = async () => {
    try {
      const next = await customerApi<any>("portal");
      setPortal(next);
      setEnrollment((current: any) =>
        current &&
        next.venues.some((v: any) =>
          v.enrollments.some(
            (e: any) => e.id === current.id && e.status === "PENDING",
          ),
        )
          ? current
          : undefined,
      );
    } catch (error) {
      if (!hasCustomerSession()) {
        setSignedIn(false);
        setPortal(undefined);
        setEnrollment(undefined);
      }
      throw error;
    }
  };
  useEffect(() => {
    if (!signedIn) return;
    void refresh().catch((e) => setError(e.message));
    const timer = setInterval(
      () => void refresh().catch((e) => setError(e.message)),
      15000,
    );
    return () => clearInterval(timer);
  }, [signedIn]);
  async function action(work: () => Promise<unknown>) {
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
  const venue = portal?.venues?.[0];
  const id = venue?.venue.id;
  async function copy(value: string) {
    try {
      await navigator.clipboard.writeText(value);
    } catch {
      setError("კოპირება ვერ მოხერხდა. მონიშნეთ კოდი და დააკოპირეთ.");
    }
  }
  return (
    <div className="customer">
      <header>
        <a href="/ka" className="customer-brand">
          Vynic
        </a>
        <span>თქვენი რესტორანი</span>
        {signedIn && (
          <button
            className="secondary"
            onClick={() => {
              customerLogout();
              setSignedIn(false);
              setPortal(undefined);
              setEnrollment(undefined);
            }}
          >
            გასვლა
          </button>
        )}
      </header>
      <main>
        <h1>
          {!signedIn
            ? "დაიწყე Vynic-ის გამოყენება"
            : !venue
              ? "თქვენი რესტორანი"
              : venue.venue.name}
        </h1>
        {error && (
          <p role="alert" className="customer-error">
            {error}
          </p>
        )}
        {!signedIn ? (
          <section className="customer-auth">
            <p>ერთი ანგარიში თქვენი რესტორნის დასაკავშირებლად.</p>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                const form = e.currentTarget;
                const data = Object.fromEntries(new FormData(form));
                void action(async () => {
                  await customerApi(
                    `auth/${signup ? "signup" : "login"}`,
                    data,
                  );
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
              {signup
                ? "უკვე გაქვთ ანგარიში? შესვლა"
                : "ახალი ანგარიშის შექმნა"}
            </button>
          </section>
        ) : !portal ? (
          <p role="status">იტვირთება…</p>
        ) : !venue ? (
          <section>
            <h2>1. რესტორანის დამატება</h2>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                const data = Object.fromEntries(new FormData(e.currentTarget));
                void action(async () => {
                  await customerApi("venues", data);
                  await refresh();
                });
              }}
            >
              <label>
                რესტორნის სახელი
                <input name="name" required maxLength={100} />
              </label>
              <label>
                დროის სარტყელი
                <input name="timezone" defaultValue="Asia/Tbilisi" required />
              </label>
              <label>
                ვალუტა
                <input
                  name="currency"
                  defaultValue="GEL"
                  minLength={3}
                  maxLength={3}
                  required
                />
              </label>
              <button disabled={busy}>გაგრძელება</button>
            </form>
          </section>
        ) : (
          <>
            <p>
              ელფოსტა: {portal.account.email}{" "}
              {!portal.account.emailVerifiedAt && "· დაუდასტურებელი"}
            </p>
            <div className="customer-columns">
              <section>
                <h2>რესტორნის კოდი</h2>
                <p className="customer-code">{venue.venue.loginCode}</p>
                <button
                  className="secondary"
                  onClick={() => void copy(venue.venue.loginCode)}
                >
                  კოდის კოპირება
                </button>
                <p>Vynic Manager-ში გამოიყენეთ ეს კოდი და მენეჯერის PIN.</p>
              </section>
              <section>
                <h2>გამოწერა</h2>
                <p>
                  {venue.subscription?.status ?? "TRIAL"}{" "}
                  {venue.subscription?.trialEndsAt &&
                    `· ${new Date(venue.subscription.trialEndsAt).toLocaleDateString("ka-GE")}`}
                </p>
                <p>{venue.features.join(" · ")}</p>
                <p>
                  {venue.ready
                    ? "POS-ის საწყისი სინქრონიზაცია დასრულებულია."
                    : "დაასრულეთ ქვემოთ მოცემული ნაბიჯები."}
                </p>
              </section>
            </div>
            <nav aria-label="გამართვის ნაბიჯები">
              {[
                ["manager", "მენეჯერი"],
                ["device", "POS-ის დაყენება"],
                ["printers", "პრინტერები"],
                ["status", "მზადყოფნა"],
              ].map(([key, label]) => (
                <button
                  key={key}
                  aria-current={step === key ? "step" : undefined}
                  className={step === key ? "" : "secondary"}
                  onClick={() => {
                    setStep(key);
                    setResetId(undefined);
                    setRequestId(crypto.randomUUID());
                  }}
                >
                  {label}
                </button>
              ))}
            </nav>
            {step === "manager" && (
              <section>
                <h2>მენეჯერის წვდომა</h2>
                {venue.managers.map((m: any) => (
                  <div className="customer-row" key={m.id}>
                    <span>
                      {m.displayName || m.username} ·{" "}
                      {m.isActive ? "აქტიური" : "გამორთული"}
                    </span>
                    <button
                      className="secondary"
                      onClick={() => {
                        setResetId(m.id);
                        setRequestId(crypto.randomUUID());
                      }}
                    >
                      PIN-ის შეცვლა
                    </button>
                    <button
                      className="secondary"
                      disabled={busy || !m.isActive}
                      onClick={() => {
                        if (confirm("გსურთ მენეჯერის წვდომის გამორთვა?"))
                          void action(async () => {
                            await customerApi(
                              `venues/${id}/managers/${m.id}/disable`,
                              { requestId: crypto.randomUUID() },
                            );
                            await refresh();
                          });
                      }}
                    >
                      გამორთვა
                    </button>
                  </div>
                ))}
                {(!venue.managers.length || resetId) && (
                  <form
                    key={resetId ?? "create"}
                    onSubmit={(e) => {
                      e.preventDefault();
                      const form = e.currentTarget;
                      const data = Object.fromEntries(new FormData(form));
                      void action(async () => {
                        await customerApi(
                          `venues/${id}/managers${resetId ? `/${resetId}/reset` : ""}`,
                          { ...data, role: "MANAGER", requestId },
                        );
                        form.reset();
                        setResetId(undefined);
                        setRequestId(crypto.randomUUID());
                        await refresh();
                        setStep("device");
                      });
                    }}
                  >
                    {!resetId && (
                      <>
                        <label>
                          მენეჯერის სახელი
                          <input name="displayName" required />
                        </label>
                        <label>
                          მომხმარებლის სახელი
                          <input
                            name="username"
                            required
                            maxLength={80}
                            autoComplete="off"
                          />
                        </label>
                      </>
                    )}
                    <label>
                      PIN
                      <input
                        name="pin"
                        type="password"
                        inputMode="numeric"
                        pattern="[0-9]{4,6}"
                        required
                        autoComplete="new-password"
                      />
                    </label>
                    <button disabled={busy}>
                      {resetId ? "ახალი PIN-ის შენახვა" : "მენეჯერის შექმნა"}
                    </button>
                    {resetId && (
                      <button
                        type="button"
                        className="secondary"
                        onClick={() => setResetId(undefined)}
                      >
                        გაუქმება
                      </button>
                    )}
                  </form>
                )}
                {venue.managers.length > 0 && (
                  <button onClick={() => setStep("device")}>
                    გაგრძელება — POS
                  </button>
                )}
              </section>
            )}
            {step === "device" && (
              <section>
                <h2>Vynic POS · მხოლოდ Windows</h2>
                <p>
                  დააყენეთ Vynic POS რესტორნის კომპიუტერზე. გახსენით პროგრამა და
                  შეიყვანეთ მოწყობილობის კოდი.
                </p>
                {enrollment && (
                  <div>
                    <p className="customer-code">{enrollment.code}</p>
                    <p>
                      ვადა:{" "}
                      {new Date(enrollment.expiresAt).toLocaleString("ka-GE")}
                    </p>
                    <button
                      className="secondary"
                      onClick={() => void copy(enrollment.code)}
                    >
                      კოდის კოპირება
                    </button>
                  </div>
                )}
                <button
                  disabled={busy}
                  onClick={() =>
                    void action(async () => {
                      if (
                        enrollment &&
                        venue.enrollments.some(
                          (e: any) =>
                            e.id === enrollment.id && e.status === "PENDING",
                        )
                      )
                        await customerApi(
                          `venues/${id}/enrollments/${enrollment.id}/cancel`,
                          {},
                        );
                      setEnrollment(
                        await customerApi(`venues/${id}/enrollments`, {}),
                      );
                      await refresh();
                    })
                  }
                >
                  {enrollment
                    ? "ახალი კოდის შექმნა"
                    : "მოწყობილობის კოდის შექმნა"}
                </button>
                {venue.enrollments
                  .filter((e: any) => e.status === "PENDING")
                  .map((e: any) => (
                    <button
                      className="secondary"
                      key={e.id}
                      disabled={busy}
                      onClick={() =>
                        void action(async () => {
                          await customerApi(
                            `venues/${id}/enrollments/${e.id}/cancel`,
                            {},
                          );
                          if (enrollment?.id === e.id) setEnrollment(undefined);
                          await refresh();
                        })
                      }
                    >
                      კოდის გაუქმება · {e.codeSelector}
                    </button>
                  ))}
                {venue.devices.map((d: any) => (
                  <p key={d.id}>
                    {d.displayName} · {d.status} ·{" "}
                    {d.lastSeenAt
                      ? `ბოლო კავშირი: ${new Date(d.lastSeenAt).toLocaleString("ka-GE")}`
                      : "კავშირის მოლოდინში"}
                  </p>
                ))}
                <h3>ჩამოტვირთვა</h3>
                {Object.entries(downloads).map(([key, label]) => (
                  <p key={key}>
                    {portal.releaseLinks[key] ? (
                      <a href={portal.releaseLinks[key]}>{label}</a>
                    ) : (
                      `${label} — ინსტალაციის ბმული ჯერ არ გამოქვეყნებულა`
                    )}
                  </p>
                ))}
                <button
                  className="secondary"
                  onClick={() => setStep("printers")}
                >
                  გაგრძელება — პრინტერები
                </button>
              </section>
            )}
            {step === "printers" && (
              <section>
                <h2>პრინტერების გამართვა</h2>
                <p>
                  შეიყვანეთ რესტორნის ქსელში არსებული პრინტერების მისამართები.
                  პარამეტრების მიღების შემდეგ POS ბეჭდავს ინტერნეტის გარეშეც.
                </p>
                {!venue.devices.length && <p>ჯერ დააკავშირეთ POS.</p>}
                {venue.devices.map((d: any) => (
                  <div key={d.id}>
                    <h3>{d.displayName}</h3>
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
                <button className="secondary" onClick={() => setStep("status")}>
                  მზადყოფნის ნახვა
                </button>
              </section>
            )}
            {step === "status" && (
              <section>
                <h2>პირველი სამუშაო დღისთვის</h2>
                <ul className="customer-checklist">
                  {Object.entries(checks).map(([key, label]) => (
                    <li key={key}>
                      {venue.checklist[key] ? "✓" : "○"} {label}
                    </li>
                  ))}
                </ul>
                <p>
                  მენიუ და მაგიდები გამართეთ რესტორნის POS-ზე. პირველი გაყიდვა
                  გამოჩნდება სინქრონიზაციის შემდეგ.
                </p>
                <button disabled={busy} onClick={() => void action(refresh)}>
                  მდგომარეობის განახლება
                </button>
              </section>
            )}
          </>
        )}
      </main>
    </div>
  );
}
