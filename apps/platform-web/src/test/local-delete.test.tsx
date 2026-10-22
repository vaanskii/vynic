import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";
import { LocalDeletePanel } from "../platform/components/LocalDeletePanel";
import { localToolsApi } from "../platform/api";
vi.mock("../platform/auth", () => ({
  useAuth: () => ({ actor: { role: "SUPER_ADMIN" } }),
}));
function show() {
  return render(
    <QueryClientProvider
      client={
        new QueryClient({ defaultOptions: { queries: { retry: false } } })
      }
    >
      <MemoryRouter>
        <LocalDeletePanel kind="venue" id="test-id" name="Tabla" />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}
describe("local deletion controls", () => {
  it("stays absent in production", async () => {
    const capability = vi
      .spyOn(localToolsApi, "capability")
      .mockResolvedValue({ enabled: false });
    show();
    await waitFor(() => expect(capability).toHaveBeenCalled());
    expect(screen.queryByText("Delete test venue")).not.toBeInTheDocument();
  });
  it("requires exact typed confirmation and shows committed media failures distinctly", async () => {
    vi.spyOn(localToolsApi, "capability").mockResolvedValue({ enabled: true });
    const remove = vi
      .spyOn(localToolsApi, "remove")
      .mockResolvedValue({
        mediaCleanup: { failures: ["file cleanup failed"] },
      });
    show();
    fireEvent.click(await screen.findByText("Delete test venue"));
    const buttons = screen.getAllByRole("button", {
      name: "Delete test venue",
    });
    const confirm = buttons[buttons.length - 1];
    expect(confirm).toBeDisabled();
    fireEvent.change(screen.getByLabelText("Type DELETE Tabla to confirm"), {
      target: { value: "DELETE Other venue" },
    });
    expect(confirm).toBeDisabled();
    expect(remove).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText("Type DELETE Tabla to confirm"), {
      target: { value: "DELETE Tabla" },
    });
    fireEvent.click(confirm);
    await screen.findByText(/database deletion succeeded/);
    expect(remove).toHaveBeenCalledWith("venue", "test-id", "DELETE Tabla");
    expect(
      screen.getByRole("link", { name: "Return to venues" }),
    ).toBeInTheDocument();
  });
});
