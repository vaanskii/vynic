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

type PendingOverride = { featureKey: string; featureName: string; effect: OverrideEffect | "INHERIT"; note?: string };

export function VenueProductTab({ venueId }: { venueId: string }) {
  const queryClient = useQueryClient();
  const product = useQuery({ queryKey: ["product", venueId], queryFn: () => platformApi.product(venueId) });
  const plans = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  const features = useQuery({ queryKey: ["features"], queryFn: platformApi.features });
  const [selectedPlanId, setSelectedPlanId] = useState("");
  const [planConfirm, setPlanConfirm] = useState(false);
  const [pendingOverride, setPendingOverride] = useState<PendingOverride | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [feedback, setFeedback] = useState<string | null>(null);
  const refresh = async () => { await queryClient.invalidateQueries({ queryKey: ["product", venueId] }); await queryClient.invalidateQueries({ queryKey: ["venues"] }); };
  const assignPlan = useMutation({ mutationFn: () => platformApi.assignPlan(venueId, selectedPlanId), onSuccess: async () => { await refresh(); setPlanConfirm(false); setFeedback("Plan assignment updated."); } });
  const override = useMutation({ mutationFn: async (change: PendingOverride) => change.effect === "INHERIT" ? platformApi.clearFeatureOverride(venueId, change.featureKey) : platformApi.setFeatureOverride(venueId, change.featureKey, change.effect, change.note?.trim() || undefined), onSuccess: async () => { await refresh(); setPendingOverride(null); setFeedback("Feature access updated."); } });

  if (product.isPending || plans.isPending || features.isPending) return <LoadingState label="Loading product access" />;
  const failed = product.error ?? plans.error ?? features.error;
  if (failed) return <ErrorState error={errorMessage(failed)} retry={() => { void product.refetch(); void plans.refetch(); void features.refetch(); }} />;
  if (!product.data || !plans.data || !features.data) return <LoadingState label="Loading product access" />;

  const state = product.data;
  const selected = selectedPlanId || state.plan?.id || "";
  const currentPlan = plans.data.find((plan) => plan.id === state.plan?.id);
  const planFeatures = new Set(currentPlan?.features.map(({ feature }) => feature.key) ?? []);

  return <>
    {feedback ? <div className="platform-feedback platform-feedback--success" role="status">{feedback}</div> : null}
    <div className="platform-grid platform-grid--sidebar">
      <Panel title="Assigned plan" description="The package assigned to this venue.">
        <div className="platform-plan-control"><div><strong>{state.plan?.name ?? "No plan assigned"}</strong><span>{state.planAssignedAt ? `Assigned ${formatDateTime(state.planAssignedAt)}` : "Assign a plan to establish inherited access."}</span></div><div><Select aria-label="Plan" value={selected} onChange={(event) => setSelectedPlanId(event.target.value)}><option value="">Select plan</option>{plans.data.map((plan) => <option key={plan.id} value={plan.id}>{plan.name} ({plan.status})</option>)}</Select><Button tone="primary" disabled={!selectedPlanId || selectedPlanId === state.plan?.id} onClick={() => setPlanConfirm(true)}>Change plan</Button></div></div>
      </Panel>
      <Panel title="Effective access" description="What this venue can use right now."><div className="platform-effective-list">{features.data.map((feature) => <div key={feature.key}><span>{feature.name}</span><StatusBadge value={state.effectiveFeatures.includes(feature.key) ? "ENABLED" : "DISABLED"} /></div>)}</div></Panel>
    </div>
    <Panel title="Feature inheritance and overrides" description="Overrides always win. Inherit removes the override and returns authority to the assigned plan.">
      <div className="platform-feature-list">{features.data.map((feature) => {
        const existing = state.overrides.find((row) => row.featureKey === feature.key);
        const effective = state.effectiveFeatures.includes(feature.key);
        const source = existing ? `Explicitly ${existing.effect.toLowerCase()}` : planFeatures.has(feature.key) ? "Included by plan" : "Inherited · not included";
        return <article className="platform-feature-row" key={feature.key}><div className={`platform-feature-icon ${effective ? "is-enabled" : ""}`}>{effective ? <CheckCircle size={21} weight="duotone" /> : <MinusCircle size={21} weight="duotone" />}</div><div className="platform-feature-row__copy"><strong>{feature.name}</strong><span className="platform-mono">{feature.key}</span><p>{source}</p><Input aria-label={`${feature.name} override note`} placeholder="Optional operator note" value={notes[feature.key] ?? existing?.note ?? ""} onChange={(event) => setNotes((current) => ({ ...current, [feature.key]: event.target.value }))} maxLength={500} /></div><div className="platform-feature-state"><StatusBadge value={effective ? "ENABLED" : "DISABLED"} /><small>{existing?.updatedAt ? `Changed ${formatDateTime(existing.updatedAt)}` : "No explicit exception"}</small></div><div className="platform-feature-actions"><Button tone={existing?.effect === "ENABLED" ? "primary" : "quiet"} onClick={() => setPendingOverride({ featureKey: feature.key, featureName: feature.name, effect: "ENABLED", note: notes[feature.key] ?? existing?.note ?? "" })}>Enable</Button><Button tone={existing?.effect === "DISABLED" ? "danger" : "quiet"} onClick={() => setPendingOverride({ featureKey: feature.key, featureName: feature.name, effect: "DISABLED", note: notes[feature.key] ?? existing?.note ?? "" })}>Disable</Button><Button tone={!existing ? "secondary" : "quiet"} disabled={!existing} onClick={() => setPendingOverride({ featureKey: feature.key, featureName: feature.name, effect: "INHERIT" })}>Inherit</Button></div></article>;
      })}</div>
    </Panel>
    {!state.website.consistent ? <div className="platform-callout platform-product-warning"><WarningCircle size={19} /><div><strong>Website configuration is inconsistent</strong><p>The configured website mode and WEBSITE entitlement disagree. Review the Website tab; the frontend has not changed either value automatically.</p></div></div> : null}
    <ConfirmDialog open={planConfirm} onOpenChange={setPlanConfirm} title="Change assigned plan?" description={`This will replace ${state.plan?.name ?? "the current empty assignment"} with ${plans.data.find((plan) => plan.id === selectedPlanId)?.name ?? "the selected plan"}. Existing feature overrides remain in place and continue to win.`} confirmLabel="Assign plan" pending={assignPlan.isPending} error={assignPlan.error ? errorMessage(assignPlan.error) : undefined} onConfirm={() => assignPlan.mutate()} />
    <ConfirmDialog open={Boolean(pendingOverride)} onOpenChange={(open) => { if (!open) setPendingOverride(null); }} title={`${pendingOverride?.effect === "INHERIT" ? "Restore plan inheritance for" : `${pendingOverride?.effect === "ENABLED" ? "Enable" : "Disable"} override for`} ${pendingOverride?.featureName ?? "feature"}?`} description={pendingOverride?.effect === "INHERIT" ? "The explicit exception will be removed. Effective access will immediately follow the assigned plan." : `This explicit ${pendingOverride?.effect.toLowerCase()} exception will override the assigned plan until it is returned to Inherit.`} confirmLabel={pendingOverride?.effect === "INHERIT" ? "Use plan value" : "Set override"} danger={pendingOverride?.effect === "DISABLED"} pending={override.isPending} error={override.error ? errorMessage(override.error) : undefined} onConfirm={() => { if (pendingOverride) override.mutate(pendingOverride); }} />
  </>;
}
