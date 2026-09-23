import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, expect, it, vi } from "vitest";
import { CatalogEditor } from "../customer/CatalogEditor";
import { customerApi } from "../customer/api";
vi.mock("../customer/api", () => ({ customerApi: vi.fn() }));
const api = vi.mocked(customerApi);
beforeEach(() => vi.clearAllMocks());
it("Cloud owner creates a category with revision and refreshes presentation", async () => {
  api.mockResolvedValue({ authority: "CLOUD", revision: 7, categories: [] });
  const saved = vi.fn();
  render(<CatalogEditor venueId="a" onSaved={saved} />);
  await userEvent.click(await screen.findByRole("button", { name: "კატეგორიის დამატება" }));
  await userEvent.type(screen.getByLabelText("სახელი ქართულად"), "ჩაი");
  await userEvent.type(screen.getByLabelText("სახელი ინგლისურად"), "Tea");
  await userEvent.click(screen.getByRole("button", { name: "შენახვა" }));
  await waitFor(() => expect(saved).toHaveBeenCalledOnce());
  expect(api).toHaveBeenCalledWith("venues/a/catalog/category", expect.objectContaining({ expectedRevision: 7, nameKa: "ჩაი", nameEn: "Tea" }), "PUT");
});
it("POS authority offers no catalog writer", async () => {
  api.mockResolvedValue({ authority: "POS", revision: 0, categories: [] });
  render(<CatalogEditor venueId="a" onSaved={vi.fn()} />);
  await screen.findByText("მენიუს სტრუქტურა და ფასები იმართება POS-ში.");
  expect(screen.queryByRole("button", { name: "კატეგორიის დამატება" })).not.toBeInTheDocument();
});
