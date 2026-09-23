import { useEffect, useState } from "react";
import { customerApi } from "./api";

type Node = {
  id: string;
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
  revision: number;
  categories: Node[];
};
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
      <p className="portal-hint">მენიუს სტრუქტურა და ფასები იმართება POS-ში.</p>
    );
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
            try {
              await customerApi(
                `venues/${venueId}/catalog/${edit.kind}`,
                {
                  id: edit.node?.id,
                  expectedRevision: data.revision,
                  categoryId: edit.categoryId,
                  subcategoryId: edit.subcategoryId,
                  menuItemId: edit.menuItemId,
                  ...(edit.kind === "variant"
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
                      }),
                },
                "PUT",
              );
              await load();
              setEdit(undefined);
              onSaved();
            } catch {
              setError(
                "შენახვა ვერ მოხერხდა. გადაამოწმეთ ველები ან განაახლეთ მენიუ და სცადეთ ხელახლა.",
              );
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
