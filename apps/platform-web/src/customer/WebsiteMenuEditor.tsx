import { useEffect, useMemo, useState } from "react";
import { customerApi } from "./api";
import { WebsiteImageUpload } from "./WebsiteImageUpload";

/**
 * The restaurant menu as the POS organizes it, with website presentation.
 *
 * Categories, subcategories, items, prices and sizes belong to the POS and are
 * read-only here. The owner decides per item whether it appears on the website
 * and, optionally, its public name, description, photo and order. Each change
 * saves one item, so there is no page-wide pending state to lose.
 */
export type OwnerMenuItem = {
  menuItemId: string;
  name: { ka: string; en: string };
  price: number;
  variantCount: number;
  variants?: { id: string; size: string; price: number }[];
  visibleOnWebsite: boolean;
  displayName: string | null;
  description: string | null;
  imageUrl: string | null;
  sortOrder: number;
  configured: boolean;
};
type Group = {
  id: string;
  slug: string;
  name: { ka: string; en: string };
  items: OwnerMenuItem[];
};
export type OwnerMenu = {
  categories: (Group & { subcategories: Group[] })[];
};

const label = (name: { ka: string; en: string }) => name.ka || name.en;
const money = (value: number) => `${value.toFixed(2)} ₾`;
const count = (category: OwnerMenu["categories"][number]) =>
  category.items.length +
  category.subcategories.reduce((n, sub) => n + sub.items.length, 0);

export function WebsiteMenuEditor({
  venueId,
  disabled = false,
  canUpload = true,
}: {
  venueId: string;
  disabled?: boolean;
  /** Photo upload needs the generic website; links still work without it. */
  canUpload?: boolean;
}) {
  const [menu, setMenu] = useState<OwnerMenu>();
  const [open, setOpen] = useState<string>();
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const path = `venues/${venueId}/website/menu`;

  const load = async () => {
    setBusy(true);
    setError("");
    try {
      setMenu(await customerApi<OwnerMenu>(path));
    } catch {
      setError("მენიუ ვერ ჩაიტვირთა. სცადეთ ხელახლა.");
    } finally {
      setBusy(false);
    }
  };
  useEffect(() => {
    void load();
  }, [venueId]);

  const save = async (item: OwnerMenuItem) => {
    setBusy(true);
    setError("");
    setMessage("");
    try {
      setMenu(
        await customerApi<OwnerMenu>(
          path,
          {
            items: [
              {
                menuItemId: item.menuItemId,
                visibleOnWebsite: item.visibleOnWebsite,
                displayName: item.displayName || null,
                description: item.description || null,
                imageUrl: item.imageUrl || null,
                sortOrder: item.sortOrder,
              },
            ],
          },
          "PUT",
        ),
      );
      setMessage(`„${item.displayName || label(item.name)}“ შენახულია.`);
      return true;
    } catch {
      setError("ცვლილება ვერ შეინახა. შეამოწმეთ ფოტო და ტექსტის სიგრძე.");
      return false;
    } finally {
      setBusy(false);
    }
  };

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!menu || !q) return menu?.categories;
    const match = (item: OwnerMenuItem) =>
      [item.name.ka, item.name.en, item.displayName ?? ""].some((v) =>
        v.toLowerCase().includes(q),
      );
    return menu.categories
      .map((c) => ({
        ...c,
        items: c.items.filter(match),
        subcategories: c.subcategories
          .map((s) => ({ ...s, items: s.items.filter(match) }))
          .filter((s) => s.items.length),
      }))
      .filter((c) => count(c));
  }, [menu, query]);

  if (!menu)
    return (
      <p role={error ? "alert" : "status"}>
        {error || "მენიუ იტვირთება…"}{" "}
        {error && (
          <button disabled={busy} onClick={() => void load()}>
            ხელახლა ცდა
          </button>
        )}
      </p>
    );
  if (menu.categories.every((c) => !count(c)))
    return (
      <div className="portal-empty">
        <strong>მენიუ ჯერ ცარიელია</strong>
        <p>
          კატეგორიები და კერძები იქმნება Vynic POS-ში. POS-ის დაკავშირების
          შემდეგ მენიუ აქ გამოჩნდება და აირჩევთ, რა გამოჩნდეს ვებსაიტზე.
        </p>
      </div>
    );

  const total = menu.categories.reduce((n, c) => n + count(c), 0);
  const visible = menu.categories.reduce(
    (n, c) =>
      n +
      [...c.items, ...c.subcategories.flatMap((s) => s.items)].filter(
        (i) => i.visibleOnWebsite,
      ).length,
    0,
  );
  const rows = (items: OwnerMenuItem[]) =>
    items.map((item) => (
      <MenuRow
        key={item.menuItemId}
        item={item}
        venueId={venueId}
        canUpload={canUpload}
        open={open === item.menuItemId}
        disabled={busy || disabled}
        onToggle={() =>
          setOpen(open === item.menuItemId ? undefined : item.menuItemId)
        }
        onSave={async (next) => {
          if (await save(next)) setOpen(undefined);
        }}
        onVisibility={(visibleOnWebsite) =>
          void save({ ...item, visibleOnWebsite })
        }
      />
    ));

  return (
    <div className="menu-tree">
      <div className="menu-tree__toolbar">
        <span>
          ვებსაიტზე ჩანს <strong>{visible}</strong> / {total} კერძი
        </span>
        <input
          type="search"
          aria-label="კერძის ძებნა"
          placeholder="კერძის ძებნა"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>
      {filtered?.map((category) => (
        <details className="menu-category" key={category.id} open>
          <summary>
            <span>{label(category.name)}</span>
            <small>{count(category)} კერძი</small>
          </summary>
          {category.items.length > 0 && (
            <ul className="menu-items">{rows(category.items)}</ul>
          )}
          {category.subcategories.map((sub) => (
            <div className="menu-subcategory" key={sub.id}>
              <h4>
                {label(sub.name)} <small>{sub.items.length}</small>
              </h4>
              <ul className="menu-items">{rows(sub.items)}</ul>
            </div>
          ))}
        </details>
      ))}
      {filtered && !filtered.length && <p>ვერაფერი მოიძებნა.</p>}
      {error && <p role="alert">{error}</p>}
      <p role="status">{busy ? "ინახება…" : message}</p>
    </div>
  );
}

function MenuRow({
  item,
  venueId,
  canUpload,
  open,
  disabled,
  onToggle,
  onSave,
  onVisibility,
}: {
  item: OwnerMenuItem;
  venueId: string;
  canUpload: boolean;
  open: boolean;
  disabled: boolean;
  onToggle: () => void;
  onSave: (item: OwnerMenuItem) => Promise<void>;
  onVisibility: (visible: boolean) => void;
}) {
  const name = label(item.name);
  return (
    <li className={`menu-item${item.visibleOnWebsite ? "" : " is-hidden"}`}>
      <div className="menu-item__row">
        <label className="portal-switch">
          <input
            type="checkbox"
            role="switch"
            aria-label={`${name} — ვებსაიტზე ჩვენება`}
            checked={item.visibleOnWebsite}
            disabled={disabled}
            onChange={(e) => onVisibility(e.target.checked)}
          />
          <span aria-hidden="true" />
        </label>
        <div className="menu-item__name">
          <strong>{item.displayName || name}</strong>
          {item.displayName && <small>POS-ში: {name}</small>}
        </div>
        <div className="menu-item__price">
          {item.variants?.length ? (
            item.variants.map((v) => (
              <span className="portal-chip" key={v.id}>
                {v.size} · {money(v.price)}
              </span>
            ))
          ) : item.variantCount > 0 ? (
            <span className="portal-chip">ზომები: {item.variantCount}</span>
          ) : (
            money(item.price)
          )}
        </div>
        <button
          type="button"
          className="secondary"
          aria-expanded={open}
          disabled={disabled}
          onClick={onToggle}
        >
          {open ? "დახურვა" : "რედაქტირება"}
        </button>
      </div>
      {open && (
        <MenuItemEditor
          item={item}
          venueId={venueId}
          canUpload={canUpload}
          disabled={disabled}
          onCancel={onToggle}
          onSave={onSave}
        />
      )}
    </li>
  );
}

/** Mounted only while open, so each opening starts from the saved item. */
function MenuItemEditor({
  item,
  venueId,
  canUpload,
  disabled,
  onCancel,
  onSave,
}: {
  item: OwnerMenuItem;
  venueId: string;
  canUpload: boolean;
  disabled: boolean;
  onCancel: () => void;
  onSave: (item: OwnerMenuItem) => Promise<void>;
}) {
  const [draft, setDraft] = useState(item);
  const [uploading, setUploading] = useState(false);
  const name = label(item.name);
  return (
    <form
      className="menu-item__editor"
      onSubmit={(e) => {
        e.preventDefault();
        void onSave(draft);
      }}
    >
      <fieldset disabled={disabled || uploading}>
        <label>
          სახელი ვებსაიტზე
          <input
            maxLength={120}
            placeholder={name}
            value={draft.displayName ?? ""}
            onChange={(e) => setDraft({ ...draft, displayName: e.target.value })}
          />
        </label>
        <label>
          აღწერა
          <textarea
            rows={3}
            maxLength={600}
            placeholder="მაგ. ხელით დაკეცილი, ხორცით და მწვანილით"
            value={draft.description ?? ""}
            onChange={(e) => setDraft({ ...draft, description: e.target.value })}
          />
        </label>
        {canUpload ? (
          <WebsiteImageUpload
            venueId={venueId}
            value={draft.imageUrl ?? ""}
            onChange={(imageUrl) => setDraft({ ...draft, imageUrl })}
            onBusy={setUploading}
            labels={{
              label: "კერძის ფოტოს ატვირთვა",
              alt: name,
              remove: "ფოტოს წაშლა",
            }}
          />
        ) : (
          <label>
            ფოტოს ბმული
            <input
              maxLength={2048}
              value={draft.imageUrl ?? ""}
              onChange={(e) => setDraft({ ...draft, imageUrl: e.target.value })}
            />
          </label>
        )}
        <details>
          <summary>რიგითობა</summary>
          <label>
            პოზიცია კატეგორიაში (ნაკლები — უფრო მაღლა)
            <input
              type="number"
              min={0}
              max={100000}
              value={draft.sortOrder}
              onChange={(e) =>
                setDraft({ ...draft, sortOrder: Number(e.target.value) })
              }
            />
          </label>
        </details>
        <div className="customer-row">
          <button>შენახვა</button>
          <button type="button" className="secondary" onClick={onCancel}>
            გაუქმება
          </button>
        </div>
      </fieldset>
    </form>
  );
}
