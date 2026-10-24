import { useEffect, useState } from "react";
import { useLocation, Link } from "react-router-dom";
import { PublicFrame } from "./PublicFrame";

export function InstallerDownloadPage() {
  const location = useLocation();
  const [token] = useState(() =>
    new URLSearchParams((location.hash || window.location.hash).slice(1)).get(
      "token",
    ),
  );
  const [data, setData] = useState<{
    available: boolean;
    expiresAt: string;
    sha256: string;
  }>();
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    fetch(
      `${(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "")}/customer/downloads/open`,
      {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": "vynic-download",
        },
        body: JSON.stringify(token ? { token } : {}),
      },
    )
      .then(async (response) => {
        const result = await response.json();
        if (!response.ok)
          throw new Error(
            "ბმული ვადაგასულია ან გაუქმებულია. შექმენით ახალი ბმული თქვენს ანგარიშში.",
          );
        if (active) {
          setData(result);
          window.history.replaceState(null, "", window.location.pathname);
        }
      })
      .catch((e) => {
        if (active) setError(e.message);
      });
    return () => {
      active = false;
    };
  }, [token]);
  return (
    <PublicFrame title="Windows ინსტალერი">
      <section className="customer-auth">
        <h1>Windows ინსტალერის ჩამოტვირთვა</h1>
        {error && <p role="alert">{error}</p>}
        {!data && !error && <p role="status">ბმული მოწმდება…</p>}
        {data?.available && (
          <>
            <p>მოქმედებს {new Date(data.expiresAt).toLocaleString("ka-GE")}.</p>
            <p>
              ჩამოტვირთეთ ZIP, სრულად ამოარქივეთ და გაუშვით VynicSetup.exe.
              შეინახეთ დანარჩენი ფაილებიც ინსტალერის გვერდით.
            </p>
            <a
              href={`${(import.meta.env.VITE_API_BASE_URL ?? "").replace(/\/$/, "")}/customer/downloads/file`}
              download
              referrerPolicy="no-referrer"
            >
              Windows პაკეტის ჩამოტვირთვა
            </a>
            <p>
              SHA-256:{" "}
              <code style={{ overflowWrap: "anywhere" }}>{data.sha256}</code>
            </p>
          </>
        )}
        {data && !data.available && (
          <p role="status">
            დაცული ჩამოტვირთვა მზადდება. მიმართეთ ადმინისტრატორს.
          </p>
        )}
        <p>
          <Link to="/dashboard/devices">
            ანგარიშში დაბრუნება და ახალი ბმულის შექმნა
          </Link>
        </p>
        <p>
          <Link to="/request-access">რეგისტრაციის მოთხოვნა</Link>
        </p>
      </section>
    </PublicFrame>
  );
}
