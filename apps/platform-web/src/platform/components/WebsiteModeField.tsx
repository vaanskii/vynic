import type { Plan, WebsiteMode } from "../types";

export const planHasWebsite = (plan?: { features?: Plan["features"] } | null) =>
  !!plan?.features?.some((f) => f.feature.key === "WEBSITE");

/**
 * Operator-only choice of how a sold Website is implemented.
 *
 * Shown whenever the chosen plan includes WEBSITE. The server refuses the
 * assignment without a choice unless the Venue already has one, so "keep
 * current" is offered only then.
 */
export function WebsiteModeField({
  current,
  value,
  onChange,
}: {
  current?: WebsiteMode | null;
  value: string;
  onChange: (value: string) => void;
}) {
  const provisioned = current === "SAAS" || current === "CUSTOM";
  const options: Array<[string, string]> = [
    ...(provisioned
      ? ([
          ["", `Keep current (${labels[current as keyof typeof labels]})`],
        ] as Array<[string, string]>)
      : []),
    ["SAAS", labels.SAAS],
    ["CUSTOM", labels.CUSTOM],
  ];
  return (
    <fieldset className="platform-website-mode">
      <legend>Website implementation</legend>
      {options.map(([mode, label]) => (
        <label key={mode || "keep"}>
          <input
            type="radio"
            name="websiteMode"
            value={mode}
            required={!provisioned}
            checked={value === mode}
            onChange={() => onChange(mode)}
          />
          {label}
        </label>
      ))}
    </fieldset>
  );
}
const labels = {
  SAAS: "Vynic SaaS website",
  CUSTOM: "Custom website (operator-managed)",
} as const;
