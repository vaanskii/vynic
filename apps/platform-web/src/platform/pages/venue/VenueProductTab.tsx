import { featureDescriptions, featureWarnings } from "../../feature-guidance";
import { useAuth } from "../../auth";
import { useState } from "react";
import { CheckCircle, MinusCircle, WarningCircle } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage, formatDateTime } from "../../format";
import type { OverrideEffect } from "../../types";
import { Button } from "../../components/Button";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { Input, Select } from "../../components/Form";
import { Panel } from "../../components/Page";
import { ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";

const featureNames: Record<string, string> = {
  ADVANCED_AUDIT: "გაფართოებული აუდიტი",
  FINANCIAL_PLANNING: "ფინანსური დაგეგმვა",
  INVENTORY: "მარაგები",
  MANAGER_APP: "მენეჯერის აპლიკაცია",
  MANAGER_RESERVATIONS: "რეზერვაციების მართვა",
  PAYROLL: "ხელფასები",
  POS: "გაყიდვების სისტემა",
  PROFITABILITY: "მომგებიანობა",
  WEBSITE: "რესტორნის ვებგვერდი",
  NON_FISCAL_CLOSE: "არაფისკალური დახურვა",
};
const featureName = (feature: { key: string; name: string }) =>
  featureNames[feature.key] ?? feature.name;

type PendingOverride = {
  featureKey: string;
  featureName: string;
  effect: OverrideEffect | "INHERIT";
  note?: string;
};

export function VenueProductTab({ venueId }: { venueId: string }) {
  const { actor } = useAuth();
  const queryClient = useQueryClient();
  const product = useQuery({
    queryKey: ["product", venueId],
    queryFn: () => platformApi.product(venueId),
  });
  const plans = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  const features = useQuery({
    queryKey: ["features"],
    queryFn: platformApi.features,
  });
  const [selectedPlanId, setSelectedPlanId] = useState("");
  const [planConfirm, setPlanConfirm] = useState(false);
  const [pendingOverride, setPendingOverride] =
    useState<PendingOverride | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [feedback, setFeedback] = useState<string | null>(null);
  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ["product", venueId] });
    await queryClient.invalidateQueries({ queryKey: ["venues"] });
  };
  const assignPlan = useMutation({
    mutationFn: () => platformApi.assignPlan(venueId, selectedPlanId),
    onSuccess: async () => {
      await refresh();
      setPlanConfirm(false);
      setFeedback("პაკეტი განახლდა.");
    },
  });
  const override = useMutation({
    mutationFn: async (change: PendingOverride) =>
      change.effect === "INHERIT"
        ? platformApi.clearFeatureOverride(venueId, change.featureKey)
        : platformApi.setFeatureOverride(
            venueId,
            change.featureKey,
            change.effect,
            change.note?.trim() || undefined,
          ),
    onSuccess: async () => {
      await refresh();
      setPendingOverride(null);
      setFeedback(
        "ფუნქციები განახლდა. დაკავშირებული აპები ცვლილებას ავტომატურად მიიღებენ დაახლოებით 10 წამში.",
      );
    },
  });

  if (product.isPending || plans.isPending || features.isPending)
    return <LoadingState label="ფუნქციები იტვირთება" />;
  const failed = product.error ?? plans.error ?? features.error;
  if (failed)
    return (
      <ErrorState
        error={errorMessage(failed)}
        retry={() => {
          void product.refetch();
          void plans.refetch();
          void features.refetch();
        }}
      />
    );
  if (!product.data || !plans.data || !features.data)
    return <LoadingState label="ფუნქციები იტვირთება" />;

  const state = product.data;
  const selected = selectedPlanId || state.plan?.id || "";
  const currentPlan = plans.data.find((plan) => plan.id === state.plan?.id);
  const planFeatures = new Set(
    currentPlan?.features.map(({ feature }) => feature.key) ?? [],
  );

  const warnings = featureWarnings(state.effectiveFeatures);
  const pendingFeatures = new Set(state.effectiveFeatures);
  if (pendingOverride) {
    const enabled = pendingOverride.effect === "INHERIT" ? planFeatures.has(pendingOverride.featureKey) : pendingOverride.effect === "ENABLED";
    if (enabled) pendingFeatures.add(pendingOverride.featureKey); else pendingFeatures.delete(pendingOverride.featureKey);
  }
  const nextPlanFeatures = new Set(plans.data.find(plan => plan.id === selectedPlanId)?.features.map(({ feature }) => feature.key) ?? []);
  for (const row of state.overrides) {
    if (row.effect === "ENABLED") nextPlanFeatures.add(row.featureKey); else nextPlanFeatures.delete(row.featureKey);
  }
  return (
    <fieldset
      disabled={actor?.role !== "SUPER_ADMIN"}
      style={{ border: 0, padding: 0, minWidth: 0 }}
    >
      {state.commercialAccess === false && (
        <p role="status" className="platform-callout">
          ღრუბლოვანი სერვისების წვდომა შეჩერებულია. აღსადგენად გაააქტიურეთ გამოწერა.
        </p>
      )}
      {warnings.length > 0 && <div role="status" className="platform-callout platform-feature-dependencies">
        <strong>ფუნქციების დამოკიდებულებები</strong>
        <ul>{warnings.map(warning => <li key={warning}>{warning}</li>)}</ul>
      </div>}
      {feedback ? (
        <div
          className="platform-feedback platform-feedback--success"
          role="status"
        >
          {feedback}
        </div>
      ) : null}
      <div className="platform-grid platform-grid--sidebar">
        <Panel
          title="მინიჭებული პაკეტი"
          description="რესტორნისთვის შერჩეული პაკეტი."
        >
          <div className="platform-plan-control">
            <div>
              <strong>{state.plan?.name ?? "პაკეტი არჩეული არ არის"}</strong>
              <span>
                {state.planAssignedAt
                  ? `მინიჭებულია ${formatDateTime(state.planAssignedAt)}`
                  : "აირჩიეთ პაკეტი."}
              </span>
            </div>
            <div>
              <Select
                aria-label="პაკეტი"
                value={selected}
                onChange={(event) => setSelectedPlanId(event.target.value)}
              >
                <option value="">აირჩიეთ პაკეტი</option>
                {plans.data.map((plan) => (
                  <option key={plan.id} value={plan.id}>
                    {plan.name} ({plan.status})
                  </option>
                ))}
              </Select>
              <Button
                tone="primary"
                disabled={!selectedPlanId || selectedPlanId === state.plan?.id}
                onClick={() => setPlanConfirm(true)}
              >
                პაკეტის შეცვლა
              </Button>
            </div>
          </div>
        </Panel>
        <Panel
          title="მოქმედი ფუნქციები"
          description="პაკეტისა და ინდივიდუალური პარამეტრების მიხედვით."
        >
          <div className="platform-effective-list">
            {features.data.map((feature) => (
              <div key={feature.key}>
                <span>{featureName(feature)}</span>
                <StatusBadge
                  value={
                    state.effectiveFeatures.includes(feature.key)
                      ? "ENABLED"
                      : "DISABLED"
                  }
                >
                  {state.effectiveFeatures.includes(feature.key)
                    ? "ჩართულია"
                    : "გამორთულია"}
                </StatusBadge>
              </div>
            ))}
          </div>
        </Panel>
      </div>
      <Panel
        title="ფუნქციები — პაკეტი და გამონაკლისები"
        description="ინდივიდუალურ პარამეტრს უპირატესობა აქვს. „პაკეტის მიხედვით“ შლის გამონაკლისს და აღადგენს პაკეტის წესს."
      >
        <div className="platform-feature-list">
          {features.data.map((feature) => {
            const existing = state.overrides.find(
              (row) => row.featureKey === feature.key,
            );
            const effective = state.effectiveFeatures.includes(feature.key);
            const source = existing
              ? existing.effect === "ENABLED"
                ? "ინდივიდუალურად ჩართულია"
                : "ინდივიდუალურად გამორთულია"
              : planFeatures.has(feature.key)
                ? "პაკეტში შედის"
                : "პაკეტში არ შედის";
            return (
              <article className="platform-feature-row" key={feature.key}>
                <div
                  className={`platform-feature-icon ${effective ? "is-enabled" : ""}`}
                >
                  {effective ? (
                    <CheckCircle size={21} weight="duotone" />
                  ) : (
                    <MinusCircle size={21} weight="duotone" />
                  )}
                </div>
                <div className="platform-feature-row__copy">
                  <strong>{featureName(feature)}</strong>

                  <p>{source}</p>
                  <p>{featureDescriptions[feature.key]}</p>
                  <Input
                    aria-label={`${featureName(feature)} — შენიშვნა`}
                    placeholder="შენიშვნა — არასავალდებულო"
                    value={notes[feature.key] ?? existing?.note ?? ""}
                    onChange={(event) =>
                      setNotes((current) => ({
                        ...current,
                        [feature.key]: event.target.value,
                      }))
                    }
                    maxLength={500}
                  />
                </div>
                <div className="platform-feature-state">
                  <StatusBadge value={effective ? "ENABLED" : "DISABLED"}>
                    {effective ? "ჩართულია" : "გამორთულია"}
                  </StatusBadge>
                  <small>
                    {existing?.updatedAt
                      ? `განახლდა ${formatDateTime(existing.updatedAt)}`
                      : "გამონაკლისი არ არის"}
                  </small>
                </div>
                <div className="platform-feature-actions">
                  <Button
                    tone={existing?.effect === "ENABLED" ? "primary" : "quiet"}
                    onClick={() =>
                      setPendingOverride({
                        featureKey: feature.key,
                        featureName: featureName(feature),
                        effect: "ENABLED",
                        note: notes[feature.key] ?? existing?.note ?? "",
                      })
                    }
                  >
                    ჩართვა
                  </Button>
                  <Button
                    tone={existing?.effect === "DISABLED" ? "danger" : "quiet"}
                    onClick={() =>
                      setPendingOverride({
                        featureKey: feature.key,
                        featureName: featureName(feature),
                        effect: "DISABLED",
                        note: notes[feature.key] ?? existing?.note ?? "",
                      })
                    }
                  >
                    გამორთვა
                  </Button>
                  <Button
                    tone={!existing ? "secondary" : "quiet"}
                    disabled={!existing}
                    onClick={() =>
                      setPendingOverride({
                        featureKey: feature.key,
                        featureName: featureName(feature),
                        effect: "INHERIT",
                      })
                    }
                  >
                    პაკეტის მიხედვით
                  </Button>
                </div>
              </article>
            );
          })}
        </div>
      </Panel>
      {!state.website.consistent ? (
        <div className="platform-callout platform-product-warning">
          <WarningCircle size={19} />
          <div>
            <strong>ვებგვერდის პარამეტრები შესამოწმებელია</strong>
            <p>
              ვებგვერდის რეჟიმი და წვდომა ერთმანეთს არ შეესაბამება. გადაამოწმეთ ვებგვერდის პარამეტრები.
            </p>
          </div>
        </div>
      ) : null}
      <ConfirmDialog
        georgian
        open={planConfirm}
        onOpenChange={setPlanConfirm}
        title="შევცვალოთ პაკეტი?"
        description={`მიმდინარე პაკეტს შეცვლის ${plans.data.find((plan) => plan.id === selectedPlanId)?.name ?? "შერჩეული პაკეტი"}. არსებული ინდივიდუალური პარამეტრები შენარჩუნდება. ${featureWarnings(nextPlanFeatures).join(" ")}`}
        confirmLabel="პაკეტის მინიჭება"
        pending={assignPlan.isPending}
        error={assignPlan.error ? errorMessage(assignPlan.error) : undefined}
        onConfirm={() => assignPlan.mutate()}
      />
      <ConfirmDialog
        georgian
        open={Boolean(pendingOverride)}
        onOpenChange={(open) => {
          if (!open) setPendingOverride(null);
        }}
        title={`${pendingOverride?.featureName ?? "ფუნქცია"} — ${pendingOverride?.effect === "INHERIT" ? "პაკეტის წესის აღდგენა" : pendingOverride?.effect === "ENABLED" ? "ჩართვა" : "გამორთვა"}?`}
        description={
          (pendingOverride?.effect === "INHERIT"
            ? "ინდივიდუალური პარამეტრი წაიშლება და ფუნქცია პაკეტის წესს დაუბრუნდება."
            : "ინდივიდუალურ პარამეტრს პაკეტის წესზე უპირატესობა ექნება.") + " " + featureWarnings(pendingFeatures).join(" ")
        }
        confirmLabel={
          pendingOverride?.effect === "INHERIT" ? "პაკეტის მიხედვით" : "შენახვა"
        }
        danger={pendingOverride?.effect === "DISABLED"}
        pending={override.isPending}
        error={override.error ? errorMessage(override.error) : undefined}
        onConfirm={() => {
          if (pendingOverride) override.mutate(pendingOverride);
        }}
      />
    </fieldset>
  );
}
