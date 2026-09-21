import { describe, expect, it } from "vitest";
import { featureWarnings, featureDescriptions } from "../platform/feature-guidance";
describe("feature dependencies", () => {
  it("distinguishes read-only POS inventory from Manager access without changing overrides", () => {
    const enabled = ["POS", "INVENTORY", "PAYROLL"];
    expect(featureWarnings(enabled).join(" ")).toContain("მხოლოდ დათვალიერება");
    expect(featureWarnings(enabled).join(" ")).toContain("ხელფასები");
    expect(enabled).toEqual(["POS", "INVENTORY", "PAYROLL"]);
    expect(featureWarnings([...enabled, "MANAGER_APP"])).toEqual([]);
  });
  it("explains profitability prerequisites and the current website limits", () => {
    expect(featureWarnings(["PROFITABILITY"])[0]).toContain("მარაგები");
    expect(featureWarnings(["NON_FISCAL_CLOSE"])[0]).toContain("POS");
    expect(featureDescriptions.PROFITABILITY).toContain("ჯერ არ მოიცავს");
    expect(featureDescriptions.WEBSITE).toContain("ავტომატურად არ ქმნის");
  });
});
