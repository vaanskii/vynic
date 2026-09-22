import { useEffect, useState } from "react";
import { customerApi } from "./api";

/**
 * Website presentation for the restaurant's existing menu.
 *
 * This is not a second menu editor. Names, prices, categories and variants
 * belong to the POS and are shown here read-only; the owner decides only
 * whether an item appears publicly and, optionally, the public name,
 * description, photograph and order it appears under.
 */
export type OwnerMenuItem = {
  menuItemId: string;
  name: { ka: string; en: string };
  price: number;
  variantCount: number;
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

const empty = (menu: OwnerMenu) =>
  menu.categories.every(
    (category) =>
      category.items.length === 0 &&
      category.subcategories.every((sub) => sub.items.length === 0),
  );

export function WebsiteMenuEditor({
  venueId,
  disabled,
}: {
  venueId: string;
  disabled: boolean;
}) {
  const [menu, setMenu] = useState<OwnerMenu>();
  const [edits, setEdits] = useState<Record<string, OwnerMenuItem>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const path = `venues/${venueId}/website/menu`;

  const accept = (next: OwnerMenu) => {
    setMenu(next);
    setEdits({});
  };
  const load = async () => {
    setBusy(true);
    setError("");
    try {
      accept(await customerApi<OwnerMenu>(path));
    } catch {
      setError("მენიუ ვერ ჩაიტვირთა. სცადეთ ხელახლა.");
    } finally {
      setBusy(false);
    }
  };
  useEffect(() => {
    void load();
  }, [venueId]);

  const value = (item: OwnerMenuItem) => edits[item.menuItemId] ?? item;
  const edit = (item: OwnerMenuItem, patch: Partial<OwnerMenuItem>) => {
    setEdits((current) => ({
      ...current,
      [item.menuItemId]: { ...value(item), ...patch },
    }));
    setMessage("");
  };
  const pending = Object.values(edits);

  const save = async () => {
    setBusy(true);
    setError("");
    setMessage("");
    try {
      accept(
        await customerApi<OwnerMenu>(
          path,
          {
            items: pending.map((item) => ({
              menuItemId: item.menuItemId,
              visibleOnWebsite: item.visibleOnWebsite,
              displayName: item.displayName || null,
              description: item.description || null,
              imageUrl: item.imageUrl || null,
              sortOrder: item.sortOrder,
            })),
          },
          "PUT",
        ),
      );
      setMessage("მენიუს ჩვენება შენახულია.");
    } catch {
      setError(
        "მენიუს ჩვენება ვერ შეინახა. შეამოწმეთ ფოტოს ბმული და ველების სიგრძე.",
      );
    } finally {
      setBusy(false);
    }
  };

  if (!menu)
    return (
      <p role={error ? "alert" : "status"}>
        {error || "მენიუ იტვირთება…"}
        {error && (
          <button disabled={busy} onClick={() => void load()}>
            ხელახლა ცდა
          </button>
        )}
      </p>
    );
  if (empty(menu))
    return (
      <p>
        POS-ზე ჯერ მენიუ არ არის შექმნილი. მენიუს შექმნის შემდეგ ის აქ
        გამოჩნდება და შეძლებთ აირჩიოთ, რა გამოჩნდეს საიტზე.
      </p>
    );

  return (
    <>
      <p>
        მენიუს სახელები და ფასები POS-ში იმართება. აქ მხოლოდ ირჩევთ, რა
        გამოჩნდეს საიტზე და როგორ.
      </p>
      {menu.categories.map((category) => (
        <fieldset key={category.id} disabled={busy || disabled}>
          <legend>{category.name.ka || category.name.en}</legend>
          <Rows items={category.items} value={value} edit={edit} />
          {category.subcategories.map((sub) => (
            <div key={sub.id}>
              <h4>{sub.name.ka || sub.name.en}</h4>
              <Rows items={sub.items} value={value} edit={edit} />
            </div>
          ))}
        </fieldset>
      ))}
      <div className="customer-row">
        <button
          disabled={busy || disabled || !pending.length}
          onClick={() => void save()}
        >
          მენიუს ჩვენების შენახვა
        </button>
        {pending.length > 0 && <span>შეუნახავი: {pending.length}</span>}
      </div>
      {error && <p role="alert">{error}</p>}
      <p role="status">{busy ? "მუშავდება…" : message}</p>
    </>
  );
}

function Rows({
  items,
  value,
  edit,
}: {
  items: OwnerMenuItem[];
  value: (item: OwnerMenuItem) => OwnerMenuItem;
  edit: (item: OwnerMenuItem, patch: Partial<OwnerMenuItem>) => void;
}) {
  if (!items.length) return null;
  return (
    <>
      {items.map((item) => {
        const current = value(item);
        const name = item.name.ka || item.name.en;
        return (
          <div className="website-menu-item" key={item.menuItemId}>
            <label>
              <input
                type="checkbox"
                checked={current.visibleOnWebsite}
                onChange={(e) =>
                  edit(item, { visibleOnWebsite: e.target.checked })
                }
              />
              <strong>{name}</strong>
            </label>
            <span className="website-menu-item__operational">
              {item.price.toFixed(2)}
              {item.variantCount > 0 && ` · ზომები: ${item.variantCount}`}
            </span>
            <label>
              საიტზე სახელი (არასავალდებულო)
              <input
                maxLength={120}
                placeholder={name}
                value={current.displayName ?? ""}
                onChange={(e) => edit(item, { displayName: e.target.value })}
              />
            </label>
            <label>
              აღწერა
              <textarea
                rows={2}
                maxLength={600}
                value={current.description ?? ""}
                onChange={(e) => edit(item, { description: e.target.value })}
              />
            </label>
            <label>
              ფოტო
              <input
                maxLength={2048}
                placeholder="ჩასვით ფოტოს ბმული"
                value={current.imageUrl ?? ""}
                onChange={(e) => edit(item, { imageUrl: e.target.value })}
              />
            </label>
            <details>
              <summary>დამატებითი პარამეტრები</summary>
              <label>
                რიგითობა
                <input
                  type="number"
                  min={0}
                  max={100000}
                  value={current.sortOrder}
                  onChange={(e) =>
                    edit(item, { sortOrder: Number(e.target.value) })
                  }
                />
              </label>
            </details>
          </div>
        );
      })}
    </>
  );
}
