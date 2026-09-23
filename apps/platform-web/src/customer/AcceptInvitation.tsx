import { useEffect, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { customerApi, customerLogout, hasCustomerSession } from "./api";
import { PublicFrame } from "./PublicFrame";

type Invitation = {
  email: string;
  organizationName: string;
  existingAccount: boolean;
};
export function AcceptInvitation() {
  const navigate = useNavigate();
  const location = useLocation();
  const [token] = useState(
    () =>
      new URLSearchParams(
        (location.hash || window.location.hash).slice(1),
      ).get("token") ?? "",
  );
  const [invitation, setInvitation] = useState<Invitation>();
  const [signedIn, setSignedIn] = useState(hasCustomerSession);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    // Keep the invitation only in memory after opening; never in query strings or storage.
    window.history.replaceState(null, "", window.location.pathname);
    if (location.hash) navigate(location.pathname, { replace: true });
    let active = true;
    customerApi<Invitation>("invitations/inspect", { token })
      .then((data) => {
        if (active) setInvitation(data);
      })
      .catch((e) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
    };
  }, [token]);
  async function accept(fields: Record<string, FormDataEntryValue>) {
    setBusy(true);
    setError("");
    try {
      if (invitation?.existingAccount && !signedIn) {
        await customerApi("auth/login", {
          email: invitation.email,
          password: fields.password,
        });
        setSignedIn(true);
      }
      const existing = signedIn || invitation?.existingAccount;
      const result = await customerApi(
        existing ? "invitations/accept" : "invitations/register",
        { ...fields, token },
      );
      navigate("/dashboard", {
        replace: true,
        state: { venueId: result.venueId },
      });
    } catch (e) {
      setError((e as Error).message);
      // An account may have been created after inspection in another tab.
      // Refresh the form choice without consuming or losing the invitation.
      try {
        setInvitation(
          await customerApi<Invitation>("invitations/inspect", { token }),
        );
      } catch {
        setInvitation(undefined);
      }
    } finally {
      setBusy(false);
    }
  }
  return (
    <PublicFrame title="მოწვევა">
      <section className="customer-auth">
        <p className="customer-eyebrow">მოწვევა Vynic-ში</p>
        <h1>რესტორანზე წვდომის მიღება</h1>
        {error && (
          <p role="alert" className="customer-error">
            {error}
          </p>
        )}
        {!invitation && !error && <p role="status">იტვირთება…</p>}
        {invitation && (
          <div className="customer-invite">
            <h2>{invitation.organizationName}</h2>
            <p className="customer-hint">{invitation.email}</p>
            <p>
              {signedIn
                ? "მიიღეთ მოწვევა თქვენი ანგარიშით."
                : invitation.existingAccount
                  ? "წვდომის მისაღებად შედით არსებული პაროლით."
                  : "შექმენით ანგარიში თქვენი რესტორნის სამართავად."}
            </p>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void accept(Object.fromEntries(new FormData(e.currentTarget)));
              }}
            >
              {!signedIn && !invitation.existingAccount && (
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
              {!signedIn && (
                <label>
                  პაროლი
                  <input
                    name="password"
                    type="password"
                    required
                    minLength={invitation.existingAccount ? 1 : 15}
                    maxLength={128}
                    autoComplete={
                      invitation.existingAccount
                        ? "current-password"
                        : "new-password"
                    }
                  />
                </label>
              )}
              {!signedIn && !invitation.existingAccount && (
                <p className="customer-hint">მინიმუმ 15 სიმბოლო.</p>
              )}
              <button disabled={busy}>
                {busy ? "მუშავდება…" : "მოწვევის მიღება"}
              </button>
            </form>
            {signedIn && (
              <button
                className="secondary"
                disabled={busy}
                onClick={() => {
                  customerLogout();
                  setSignedIn(false);
                  setError("");
                }}
              >
                სხვა ანგარიშით შესვლა
              </button>
            )}
          </div>
        )}
        {!invitation && error && (
          <p>მოითხოვეთ ახალი მოწვევა Vynic-ის ადმინისტრატორთან.</p>
        )}
      </section>
    </PublicFrame>
  );
}
