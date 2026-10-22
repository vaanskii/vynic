import { ArrowRight, Check, CheckCircle, Plus } from "@phosphor-icons/react";
import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import posScreen from "../assets/pos-live-floor.jpg";
import vynicLogo from "../assets/vynic-logo.png";
import { customerApi } from "./api";
import { PublicFrame } from "./PublicFrame";
import "./access-request.css";

type Plan = { id: string; name: string };

export function AccessRequest() {
  const [plans, setPlans] = useState<Plan[]>([]);
  const [plansUnavailable, setPlansUnavailable] = useState(false);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState("");
  const successTitle = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    let active = true;
    customerApi<Plan[]>("access-requests/plans")
      .then((result) => {
        if (active) setPlans(result);
      })
      .catch(() => {
        if (active) setPlansUnavailable(true);
      });
    return () => {
      active = false;
    };
  }, []);
  useEffect(() => {
    if (sent) successTitle.current?.focus();
  }, [sent]);

  return (
    <PublicFrame title="გამოსცადე Vynic">
      <div className="access-layout">
        <aside className="access-story" aria-label="Vynic — რესტორნის მართვა">
          <div className="access-brand">
            <img src={vynicLogo} alt="" />
            <span>Vynic</span>
          </div>
          <div className="access-intro">
            <p className="access-eyebrow">მეტი დრო სტუმრებისთვის</p>
            <h2>
              ახალი სივრცე
              <br />
              თქვენი რესტორნისთვის.
            </h2>
            <p>
              POS, ვებსაიტი და მართვის პანელი —<br />
              აირჩიეთ ის, რაც თქვენს ბიზნესს სჭირდება.
            </p>
          </div>
          <div className="access-preview" aria-hidden="true">
            <div className="access-preview-window">
              <div className="access-preview-bar">
                <span />
                <span />
                <span />
                <b>Vynic POS</b>
              </div>
              <img src={posScreen} alt="" width={800} height={632} />
            </div>
            <div className="access-preview-note">
              <span>
                <Check size={16} weight="bold" />
              </span>
              თქვენი რესტორნის რიტმში
            </div>
          </div>
          <ol className="access-steps" aria-label="როგორ დავიწყოთ">
            <li>
              <span>01</span>
              <div>
                <strong>გამოგვიგზავნეთ განაცხადი</strong>
                <p>მოგვიყევით თქვენი ბიზნესის შესახებ.</p>
              </div>
            </li>
            <li>
              <span>02</span>
              <div>
                <strong>ერთად შევარჩიოთ პაკეტი</strong>
                <p>ჩვენი გუნდი დაგიკავშირდებათ.</p>
              </div>
            </li>
            <li>
              <span>03</span>
              <div>
                <strong>მიიღეთ მოწვევა</strong>
                <p>დამტკიცების შემდეგ გახსენით თქვენი სივრცე.</p>
              </div>
            </li>
          </ol>
        </aside>
        <section className="access-panel" aria-labelledby="access-title">
          <nav className="auth-mode" aria-label="ანგარიშზე წვდომა">
            <Link to="/login">შესვლა</Link>
            <Link to="/request-access" aria-current="page">
              გამოსცადე Vynic
            </Link>
          </nav>
          {sent ? (
            <div className="access-success">
              <CheckCircle size={56} weight="light" aria-hidden="true" />
              <p className="access-eyebrow">პირველი ნაბიჯი გადადგმულია</p>
              <h1 id="access-title" ref={successTitle} tabIndex={-1}>
                განაცხადი მიღებულია
              </h1>
              <p>
                ჩვენი გუნდი დაგიკავშირდებათ მითითებულ ელფოსტაზე ან ტელეფონზე.
                დამტკიცების შემდეგ მიიღებთ მოწვევას თქვენს მართვის პანელში.
              </p>
              <Link className="access-home" to="/ka">
                მთავარ გვერდზე დაბრუნება{" "}
                <ArrowRight size={18} aria-hidden="true" />
              </Link>
            </div>
          ) : (
            <div className="access-form-content">
              <h1 id="access-title">გამოსცადე Vynic</h1>
              <p className="access-lead">
                დავიწყოთ თქვენი ბიზნესით. შეავსეთ განაცხადი და ერთად შევარჩიოთ
                შესაფერისი პაკეტი.
              </p>
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  const body = Object.fromEntries(
                    new FormData(e.currentTarget),
                  );
                  setBusy(true);
                  setError("");
                  try {
                    await customerApi("access-requests", body);
                    setSent(true);
                  } catch (e) {
                    if (
                      (e as Error).message ===
                      "A request is already awaiting review"
                    )
                      setSent(true);
                    else setError((e as Error).message);
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                <fieldset disabled={busy}>
                  <legend className="sr-only">
                    საკონტაქტო ინფორმაცია და სასურველი პაკეტი
                  </legend>
                  <label>
                    თქვენი სახელი
                    <input
                      name="applicantName"
                      required
                      maxLength={100}
                      autoComplete="name"
                      placeholder="მაგ. ნინო"
                    />
                  </label>
                  <label>
                    რესტორნის / ბიზნესის სახელი
                    <input
                      name="businessName"
                      required
                      maxLength={100}
                      autoComplete="organization"
                      placeholder="თქვენი ბიზნესის სახელი"
                    />
                  </label>
                  <div className="access-contact-row">
                    <label>
                      ელფოსტა
                      <input
                        name="email"
                        type="email"
                        required
                        maxLength={254}
                        autoComplete="email"
                        placeholder="name@example.com"
                      />
                    </label>
                    <label>
                      ტელეფონი
                      <input
                        name="phone"
                        type="tel"
                        required
                        maxLength={40}
                        autoComplete="tel"
                        placeholder="+995 555 00 00 00"
                      />
                    </label>
                  </div>
                  <label>
                    სასურველი პაკეტი
                    <select
                      name="requestedPlanId"
                      aria-describedby={
                        plansUnavailable ? "access-plans-hint" : undefined
                      }
                    >
                      <option value="">შერჩევაში დახმარება მჭირდება</option>
                      {plans.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  {plansUnavailable && (
                    <p
                      id="access-plans-hint"
                      className="access-hint"
                      role="status"
                    >
                      პაკეტების სია ვერ ჩაიტვირთა. გამოგზავნეთ განაცხადი და
                      შერჩევაში დაგეხმარებით.
                    </p>
                  )}
                  <details className="access-note">
                    <summary>
                      <Plus size={16} aria-hidden="true" /> დამატებითი
                      ინფორმაცია <span>არასავალდებულო</span>
                    </summary>
                    <label>
                      <span className="sr-only">დამატებითი ინფორმაცია</span>
                      <textarea
                        name="note"
                        maxLength={1000}
                        rows={3}
                        placeholder="რისი გამარტივება გსურთ თქვენს ბიზნესში?"
                      />
                    </label>
                  </details>
                  {error && (
                    <p role="alert" className="customer-error">
                      {error}
                    </p>
                  )}
                  <button
                    className="auth-submit"
                    disabled={busy}
                    aria-busy={busy}
                  >
                    {busy ? "იგზავნება…" : "განაცხადის გაგზავნა"}
                    <ArrowRight size={18} aria-hidden="true" />
                  </button>
                </fieldset>
                <p className="access-hint access-submit-hint">
                  გაგზავნის შემდეგ ჩვენი გუნდი დაგიკავშირდებათ.
                </p>
              </form>
            </div>
          )}
        </section>
      </div>
    </PublicFrame>
  );
}
