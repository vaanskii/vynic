import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, it, vi } from "vitest";
import { CatalogEditor } from "../customer/CatalogEditor";
import { CustomerApiError, customerApi } from "../customer/api";
vi.mock("../customer/api", async (original) => ({
  ...(await original<typeof import("../customer/api")>()),
  customerApi: vi.fn(),
}));
const api = vi.mocked(customerApi);
beforeEach(() => vi.clearAllMocks());
const item = {
  id: "11111111-1111-4111-8111-111111111111",
  revision: 42,
  nameKa: "ხინკალი",
  nameEn: "Khinkali",
  price: 20,
  enabled: true,
  sortOrder: 0,
  variants: [],
};
const catalog = {
  authority: "CLOUD",
  sequence: 7,
  categories: [
    {
      id: "22222222-2222-4222-8222-222222222222",
      revision: 1,
      nameKa: "კერძები",
      nameEn: "Dishes",
      sortOrder: 0,
      items: [item],
      subcategories: [],
    },
  ],
};
it("Cloud owner creates a category as a canonical mutation and refreshes presentation", async () => {
  api.mockResolvedValue({ authority: "CLOUD", sequence: 7, categories: [] });
  const saved = vi.fn();
  render(<CatalogEditor venueId="a" onSaved={saved} />);
  await userEvent.click(await screen.findByRole("button", { name: "კატეგორიის დამატება" }));
  await userEvent.type(screen.getByLabelText("სახელი ქართულად"), "ჩაი");
  await userEvent.type(screen.getByLabelText("სახელი ინგლისურად"), "Tea");
  await userEvent.click(screen.getByRole("button", { name: "შენახვა" }));
  await waitFor(() => expect(saved).toHaveBeenCalledOnce());
  expect(api).toHaveBeenCalledWith(
    "venues/a/catalog/mutations",
    expect.objectContaining({
      entityType: "CATEGORY",
      operation: "UPSERT",
      expectedRevision: 0,
      mutationId: expect.any(String),
      entityId: expect.any(String),
      patch: expect.objectContaining({ nameKa: "ჩაი", nameEn: "Tea" }),
    }),
  );
});
it("an edit is based on the item's own revision, and a conflict never overwrites", async () => {
  api.mockImplementation(async (path, body) => {
    if (body === undefined) return catalog;
    throw new CustomerApiError("conflict", 409, {
      code: "REVISION_CONFLICT",
      conflict: {
        currentRevision: 43,
        deleted: false,
        current: { ...item, price: 22, revision: 43 },
      },
    });
  });
  render(<CatalogEditor venueId="a" onSaved={vi.fn()} />);
  await userEvent.click((await screen.findAllByRole("button", { name: "შეცვლა" }))[0]);
  const price = screen.getByLabelText("ფასი");
  await userEvent.clear(price);
  await userEvent.type(price, "21");
  await userEvent.click(screen.getByRole("button", { name: "შენახვა" }));
  await screen.findByText("ეს ელემენტი სხვა მოწყობილობაზე შეიცვალა.");
  const sent = api.mock.calls.find(([, body]) => body !== undefined)![1] as Record<string, unknown>;
  expect(sent).toMatchObject({ entityId: item.id, expectedRevision: 42, patch: { price: 21 } });
  // Both values are shown; nothing was re-sent automatically.
  expect(screen.getByRole("alertdialog")).toHaveTextContent("22");
  expect(screen.getByRole("alertdialog")).toHaveTextContent("21");
  expect(api.mock.calls.filter(([, body]) => body !== undefined)).toHaveLength(1);
  // Re-apply is explicit, against the current revision, with a new mutation id.
  api.mockImplementation(async (path, body) =>
    body === undefined ? catalog : { status: "ACCEPTED" },
  );
  await userEvent.click(
    screen.getByRole("button", { name: "ჩემი ცვლილების ხელახლა გამოყენება" }),
  );
  await waitFor(() =>
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument(),
  );
  const writes = api.mock.calls.filter(([, body]) => body !== undefined);
  expect(writes[1][1]).toMatchObject({
    expectedRevision: 43,
    resolution: "REAPPLY",
    patch: { price: 21 },
  });
  expect((writes[1][1] as Record<string, unknown>).mutationId).not.toBe(
    sent.mutationId,
  );
});
it("use current discards the pending change and reloads", async () => {
  api.mockImplementation(async (path, body) => {
    if (body === undefined) return catalog;
    throw new CustomerApiError("conflict", 409, {
      code: "REVISION_CONFLICT",
      conflict: { currentRevision: 43, deleted: true, current: null },
    });
  });
  render(<CatalogEditor venueId="a" onSaved={vi.fn()} />);
  await userEvent.click((await screen.findAllByRole("button", { name: "შეცვლა" }))[0]);
  await userEvent.click(screen.getByRole("button", { name: "შენახვა" }));
  await screen.findByText("ეს ელემენტი სხვა მოწყობილობაზე წაიშალა.");
  expect(
    screen.queryByRole("button", { name: "ჩემი ცვლილების ხელახლა გამოყენება" }),
  ).not.toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: "მიმდინარეს გამოყენება" }));
  await waitFor(() =>
    expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument(),
  );
  expect(api.mock.calls.filter(([, body]) => body !== undefined)).toHaveLength(1);
});
it("a network retry of the same change reuses its mutation id", async () => {
  let attempts = 0;
  api.mockImplementation(async (path, body) => {
    if (body === undefined) return catalog;
    attempts += 1;
    if (attempts === 1) throw new Error("offline");
    return { status: "ACCEPTED" };
  });
  const saved = vi.fn();
  render(<CatalogEditor venueId="a" onSaved={saved} />);
  await userEvent.click((await screen.findAllByRole("button", { name: "შეცვლა" }))[0]);
  await userEvent.click(screen.getByRole("button", { name: "შენახვა" }));
  await screen.findByText(/შენახვა ვერ მოხერხდა/);
  await userEvent.click(screen.getByRole("button", { name: "შენახვა" }));
  await waitFor(() => expect(saved).toHaveBeenCalledOnce());
  const writes = api.mock.calls.filter(([, body]) => body !== undefined);
  const ids = writes.map(([, body]) => (body as Record<string, unknown>).mutationId);
  expect(ids[0]).toBe(ids[1]);
});
it("POS authority offers no catalog writer", async () => {
  api.mockResolvedValue({ authority: "POS", sequence: 0, categories: [] });
  render(<CatalogEditor venueId="a" onSaved={vi.fn()} />);
  await screen.findByText("მენიუს სტრუქტურა და ფასები იმართება POS-ში.");
  expect(screen.queryByRole("button", { name: "კატეგორიის დამატება" })).not.toBeInTheDocument();
});
