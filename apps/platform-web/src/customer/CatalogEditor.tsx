import { useEffect, useRef, useState } from "react";
import { CustomerApiError, customerApi } from "./api";

type Node = {
  id: string;
  /** This node's own revision; edits to other products never conflict with it. */
  revision: number;
  nameKa: string;
  nameEn: string;
  sortOrder: number;
  price?: number;
  enabled?: boolean;
  size?: number;
  items?: Node[];
  subcategories?: Node[];
  variants?: Node[];
};
type Catalog = {
  authority: "POS" | "CLOUD";
  editingEnabled?: boolean;
  posIncluded?: boolean;
  /** The Venue change sequence (catch-up cursor), not an edit precondition. */
  sequence: number;
  categories: Node[];
};
const kinds: Record<string, string> = {
  category: "CATEGORY",
  subcategory: "SUBCATEGORY",
  item: "ITEM",
  variant: "VARIANT",
};
/** One canonical mutation (docs/CANONICAL_MENU_SYNC.md). */
type Mutation = {
  mutationId: string;
  entityType: string;
  operation: "UPSERT";
  entityId: string;
  expectedRevision: number;
  patch: Record<string, unknown>;
  resolution?: "REAPPLY";
};
type Conflict = {
  mutation: Mutation;
  currentRevision: number;
  deleted: boolean;
  current: Record<string, unknown> | null;
};
const fieldLabels: Record<string, string> = {
  nameKa: "სახელი (ქართ.)",
  nameEn: "სახელი (ინგლ.)",
  price: "ფასი",
  size: "ზომა",
  enabled: "ჩართულია",
  sortOrder: "რიგითობა",
};
const show = (value: unknown) =>
  typeof value === "boolean"
    ? value
      ? "კი"
      : "არა"
    : typeof value === "number"
      ? String(value)
      : String(value ?? "—");
type Edit = {
  kind: string;
  node?: Node;
  categoryId?: string;
  subcategoryId?: string;
  menuItemId?: string;
};
export function CatalogEditor({
  venueId,
  onSaved,
}: {
  venueId: string;
  onSaved: () => void;
}) {
  const [data, setData] = useState<Catalog>();
  const [edit, setEdit] = useState<Edit>();
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [conflict, setConflict] = useState<Conflict>();
  // A retry of the SAME change reuses its id, so a lost response never applies twice.
  const retry = useRef<{ key: string; mutationId: string; entityId: string } | undefined>(
    undefined,
  );
  async function send(mutation: Mutation) {
    try {
      await customerApi(`venues/${venueId}/catalog/mutations`, mutation);
      setConflict(undefined);
      await load();
      // Keep the accepted mutation's identity until its presentation reloads.
      // Otherwise a reload failure leaves the form open as a second create.
      retry.current = undefined;
      setEdit(undefined);
      onSaved();
    } catch (failure) {
      if (
        failure instanceof CustomerApiError &&
        failure.data?.code === "REVISION_CONFLICT"
      ) {
        retry.current = undefined;
        const c = failure.data.conflict as Omit<Conflict, "mutation">;
        setConflict({
          mutation,
          currentRevision: c.currentRevision,
          deleted: c.deleted,
          current: c.current,
        });
        return;
      }
      setError(
        "შენახვა ვერ მოხერხდა. გადაამოწმეთ ველები ან განაახლეთ მენიუ და სცადეთ ხელახლა.",
      );
    }
  }
  async function load() {
    setData(await customerApi<Catalog>(`venues/${venueId}/catalog`));
  }
  useEffect(() => {
    void load().catch(() => setError("მენიუ ვერ ჩაიტვირთა. სცადეთ ხელახლა."));
  }, [venueId]);
  if (!data)
    return (
      <section className="portal-card">
        <p role={error ? "alert" : "status"}>{error || "იტვირთება…"}</p>
        {error && (
          <button
            onClick={() =>
              void load().catch(() => setError("მენიუ ვერ ჩაიტვირთა."))
            }
          >
            განახლება
          </button>
        )}
      </section>
    );
  if (data.authority === "POS")
    return (
      <p className="portal-hint">
        {data.posIncluded === false
          ? "მენიუს მართვის ჩართვას Vynic-ის გუნდი ასრულებს."
          : "მენიუს სტრუქტურა და ფასები იმართება POS-ში."}
      </p>
    );
  if (data.editingEnabled === false) return <p className="portal-hint">Dashboard-ში მენიუს რედაქტირება გამორთულია. ჩასართავად დაუკავშირდით Vynic-ს.</p>;
  const action = (label: string, value: Edit) => (
    <button
      type="button"
      className="secondary"
      onClick={() => {
        setEdit(value);
        setError("");
      }}
    >
      {label}
    </button>
  );
  const items = (rows: Node[], parent: Edit) =>
    rows.map((item) => (
      <li key={item.id}>
        <div className="customer-row">
          <strong>{item.nameKa || item.nameEn}</strong>
          <span>
            {item.price?.toFixed(2)}
            {item.enabled === false ? " · გამორთულია" : ""}
          </span>
          {action("შეცვლა", { ...parent, kind: "item", node: item })}
          {action("ზომის დამატება", { kind: "variant", menuItemId: item.id })}
        </div>
        {!!item.variants?.length && (
          <ul>
            {item.variants.map((v) => (
              <li key={v.id}>
                <span>
                  {v.size} · {v.price?.toFixed(2)}{" "}
                </span>
                {action("ზომის შეცვლა", {
                  kind: "variant",
                  menuItemId: item.id,
                  node: v,
                })}
              </li>
            ))}
          </ul>
        )}
      </li>
    ));
  return (
    <section className="portal-card">
      <h3>რესტორნის მენიუ</h3>
      <p className="portal-hint">
        დაამატეთ კატეგორიები, კერძები და ფასები. ქვემოთ ცალკე შეცვალეთ მათი
        აღწერა და ფოტო ვებსაიტისთვის.
      </p>
      {action("კატეგორიის დამატება", { kind: "category" })}
      {!data.categories.length && (
        <p>მენიუ ჯერ ცარიელია. დაიწყეთ კატეგორიის დამატებით.</p>
      )}
      {data.categories.map((cat) => (
        <details key={cat.id} open>
          <summary>{cat.nameKa || cat.nameEn}</summary>
          <div className="customer-row">
            {action("კატეგორიის შეცვლა", { kind: "category", node: cat })}
            {action("ქვეკატეგორიის დამატება", {
              kind: "subcategory",
              categoryId: cat.id,
            })}
            {action("კერძის დამატება", { kind: "item", categoryId: cat.id })}
          </div>
          <ul>
            {items(cat.items || [], { kind: "item", categoryId: cat.id })}
          </ul>
          {cat.subcategories?.map((sub) => (
            <details key={sub.id} open>
              <summary>{sub.nameKa || sub.nameEn}</summary>
              <div className="customer-row">
                {action("ქვეკატეგორიის შეცვლა", {
                  kind: "subcategory",
                  categoryId: cat.id,
                  node: sub,
                })}
                {action("კერძის დამატება", {
                  kind: "item",
                  subcategoryId: sub.id,
                })}
              </div>
              <ul>
                {items(sub.items || [], {
                  kind: "item",
                  subcategoryId: sub.id,
                })}
              </ul>
            </details>
          ))}
        </details>
      ))}
      {edit && (
        <form
          key={`${edit.kind}-${edit.node?.id || edit.categoryId || edit.subcategoryId || edit.menuItemId || "new"}`}
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            setError("");
            const f = new FormData(e.currentTarget);
            const patch: Record<string, unknown> =
              edit.kind === "variant"
                ? {
                    size: Number(f.get("size")),
                    price: Number(f.get("price")),
                  }
                : {
                    nameKa: f.get("nameKa"),
                    nameEn: f.get("nameEn"),
                    sortOrder: Number(f.get("sortOrder")),
                    ...(edit.kind === "item"
                      ? {
                          price: Number(f.get("price")),
                          enabled: f.has("enabled"),
                        }
                      : {}),
                  };
            // A new node names its parent; an existing one keeps it.
            if (!edit.node) {
              if (edit.categoryId && edit.kind !== "category")
                patch.categoryId = edit.categoryId;
              if (edit.subcategoryId) patch.subcategoryId = edit.subcategoryId;
              if (edit.menuItemId) patch.menuItemId = edit.menuItemId;
            }
            const content = {
              entityType: kinds[edit.kind],
              operation: "UPSERT" as const,
              entityId: edit.node?.id ?? crypto.randomUUID(),
              expectedRevision: edit.node?.revision ?? 0,
              patch,
            };
            const key = JSON.stringify(
              edit.node ? content : { ...content, entityId: edit.kind },
            );
            if (retry.current?.key !== key)
              retry.current = { key, mutationId: crypto.randomUUID(), entityId: content.entityId };
            try {
              await send({ ...content, entityId: retry.current.entityId, mutationId: retry.current.mutationId });
            } finally {
              setBusy(false);
            }
          }}
        >
          <fieldset disabled={busy}>
            <legend>{edit.node ? "შეცვლა" : "დამატება"}</legend>
            {edit.kind !== "variant" && (
              <>
                <label>
                  სახელი ქართულად
                  <input
                    name="nameKa"
                    required
                    maxLength={120}
                    defaultValue={edit.node?.nameKa}
                  />
                </label>
                <label>
                  სახელი ინგლისურად
                  <input
                    name="nameEn"
                    required
                    maxLength={120}
                    defaultValue={edit.node?.nameEn}
                  />
                </label>
                <label>
                  რიგითობა
                  <input
                    name="sortOrder"
                    type="number"
                    min={0}
                    max={1000000}
                    step={1}
                    defaultValue={edit.node?.sortOrder ?? 0}
                  />
                </label>
              </>
            )}
            {edit.kind === "variant" && (
              <label>
                ზომა (ლ)
                <input
                  name="size"
                  type="number"
                  required
                  min={0.001}
                  step="any"
                  defaultValue={edit.node?.size}
                />
              </label>
            )}
            {["item", "variant"].includes(edit.kind) && (
              <label>
                ფასი
                <input
                  name="price"
                  type="number"
                  required
                  min={0}
                  max={1000000}
                  step="0.01"
                  defaultValue={edit.node?.price ?? 0}
                />
              </label>
            )}
            {edit.kind === "item" && (
              <label>
                <input
                  name="enabled"
                  type="checkbox"
                  defaultChecked={edit.node?.enabled ?? true}
                />
                ჩართულია
              </label>
            )}
            <div className="customer-row">
              <button>{busy ? "ინახება…" : "შენახვა"}</button>
              <button
                type="button"
                className="secondary"
                onClick={() => setEdit(undefined)}
              >
                გაუქმება
              </button>
            </div>
          </fieldset>
        </form>
      )}
      {conflict && (
        <div className="portal-card" role="alertdialog" aria-label="ცვლილებების კონფლიქტი">
          <p role="alert">
            {conflict.deleted
              ? "ეს ელემენტი სხვა მოწყობილობაზე წაიშალა."
              : "ეს ელემენტი სხვა მოწყობილობაზე შეიცვალა."}
          </p>
          <table>
            <thead>
              <tr>
                <th></th>
                <th>მიმდინარე</th>
                <th>თქვენი ცვლილება</th>
              </tr>
            </thead>
            <tbody>
              {Object.keys(conflict.mutation.patch)
                .filter((field) => fieldLabels[field])
                .map((field) => (
                  <tr key={field}>
                    <th>{fieldLabels[field]}</th>
                    <td>
                      {conflict.deleted ? "—" : show(conflict.current?.[field])}
                    </td>
                    <td>{show(conflict.mutation.patch[field])}</td>
                  </tr>
                ))}
            </tbody>
          </table>
          <div className="customer-row">
            <button
              type="button"
              onClick={() => {
                setConflict(undefined);
                setEdit(undefined);
                void load();
              }}
            >
              მიმდინარეს გამოყენება
            </button>
            {!conflict.deleted && (
              <button
                type="button"
                className="secondary"
                disabled={busy}
                onClick={async () => {
                  setBusy(true);
                  try {
                    await send({
                      ...conflict.mutation,
                      mutationId: crypto.randomUUID(),
                      expectedRevision: conflict.currentRevision,
                      resolution: "REAPPLY",
                    });
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                ჩემი ცვლილების ხელახლა გამოყენება
              </button>
            )}
          </div>
        </div>
      )}
      {error && (
        <>
          <p role="alert">{error}</p>
          <button
            type="button"
            onClick={() =>
              void load()
                .then(() => setError(""))
                .catch(() => setError("განახლება ვერ მოხერხდა."))
            }
          >
            მენიუს განახლება
          </button>
        </>
      )}
    </section>
  );
}
