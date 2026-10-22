import {
  formatPrice,
  itemName,
  WebsiteApiError,
  type CustomSiteBootstrap,
  type MenuItem,
} from "@vynic/website-client";
import { useState, type FormEvent } from "react";
import { client, hooks, SITE_KEY } from "./site";

/**
 * Starter layout for a CUSTOM restaurant website.
 *
 * Everything below the data hooks is meant to be replaced by the client's own
 * design. The hooks and client are the shared part: identity, menu,
 * availability and paid booking all come from the Vynic backend for whichever
 * restaurant owns the Host this page was served on.
 */
export function App() {
  const site = hooks.useSite(SITE_KEY);

  if (site.state === "loading") return <p className="state">Loading…</p>;
  if (site.state === "unavailable")
    return <p className="state">This website is not available.</p>;
  if (site.state === "error")
    return <p className="state">Something went wrong. Please try again.</p>;
  if (site.data.kind === "misattached")
    // A deployment mistake, not a visitor problem: keep the page neutral and
    // leave the detail for whoever deployed it.
    return (
      <p
        className="state"
        data-site-error="misattached"
        data-expected={site.data.expected}
        data-bound={site.data.bound ?? ""}
      >
        This website is temporarily unavailable.
      </p>
    );
  if (site.data.kind === "setup")
    return (
      <main className="page">
        <h1>{site.data.bootstrap.profile.name}</h1>
        <p className="state">Our new website is coming soon.</p>
      </main>
    );
  return <Restaurant bootstrap={site.data.bootstrap} />;
}

function Restaurant({ bootstrap }: { bootstrap: CustomSiteBootstrap }) {
  const { profile, capabilities } = bootstrap;
  return (
    <main className="page">
      <header>
        <h1>{profile.name}</h1>
        {profile.branchName && <p>{profile.branchName}</p>}
      </header>
      {capabilities.menu && <Menu />}
      {capabilities.reservations && <Booking />}
      <footer>
        {profile.address && <p>{profile.address}</p>}
        {profile.phone && <a href={`tel:${profile.phone}`}>{profile.phone}</a>}
      </footer>
    </main>
  );
}

function Menu() {
  const menu = hooks.useMenu();
  if (menu.state !== "ready" || !menu.data) return null;
  const { categories, currency } = menu.data;
  const row = (item: MenuItem) => (
    <li key={item.id}>
      <span>{itemName(item, "ka")}</span>
      <span>{formatPrice(item.price, currency)}</span>
    </li>
  );
  return (
    <section aria-labelledby="menu-title">
      <h2 id="menu-title">მენიუ</h2>
      {categories.map((category) => (
        <article key={category.id}>
          <h3>{category.name.ka}</h3>
          <ul>{category.items.map(row)}</ul>
          {category.subcategories.map((sub) => (
            <div key={sub.id}>
              <h4>{sub.name.ka}</h4>
              <ul>{sub.items.map(row)}</ul>
            </div>
          ))}
        </article>
      ))}
    </section>
  );
}

function Booking() {
  const [date, setDate] = useState("");
  const [table, setTable] = useState("");
  const [time, setTime] = useState("19:00");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const availability = hooks.useAvailability(date || null);
  const free =
    availability.state === "ready"
      ? availability.data.filter((t) => t.isAvailable)
      : [];

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      // Prices, Venue and payment credentials are decided by the server.
      const result = await client.bookAndPay({
        selectedTables: [table],
        selectedDate: date,
        selectedTime: time,
        customerName: name,
        customerPhone: phone,
        language: "ka",
      });
      if (result.redirect_url) window.location.assign(result.redirect_url);
    } catch (e) {
      setError(e instanceof WebsiteApiError ? e.message : "Booking failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section aria-labelledby="booking-title">
      <h2 id="booking-title">დაჯავშნა</h2>
      <form onSubmit={submit}>
        <label>
          თარიღი
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            required
          />
        </label>
        <label>
          მაგიდა
          <select
            value={table}
            onChange={(e) => setTable(e.target.value)}
            required
            disabled={!free.length}
          >
            <option value="">—</option>
            {free.map((t) => (
              <option key={t.id} value={t.tableNumber}>
                {t.tableNumber} · {t.capacity}
              </option>
            ))}
          </select>
        </label>
        <label>
          დრო
          <input
            type="time"
            value={time}
            onChange={(e) => setTime(e.target.value)}
            required
          />
        </label>
        <label>
          სახელი
          <input value={name} onChange={(e) => setName(e.target.value)} required />
        </label>
        <label>
          ტელეფონი
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            required
          />
        </label>
        {error && <p role="alert">{error}</p>}
        <button disabled={busy}>დაჯავშნა და გადახდა</button>
      </form>
    </section>
  );
}
