import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../api";
import { useAuth } from "../auth";
import { errorMessage } from "../format";
import type { Plan } from "../types";
import { Button } from "../components/Button";
import { PageHeader, Panel } from "../components/Page";
import { ErrorState, LoadingState } from "../components/State";
import { StatusBadge } from "../components/StatusBadge";
import { Field, Input, Select } from "../components/Form";
export function PlansPage() {
  const { actor } = useAuth();
  const client = useQueryClient();
  const plans = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  const features = useQuery({
    queryKey: ["features"],
    queryFn: platformApi.features,
  });
  const addWebsite = useMutation({
    mutationFn: platformApi.ensureWebsitePlan,
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ["plans"] });
    },
  });
  const [editing, setEditing] = useState<Plan | "new" | null>(null);
  const save = useMutation({
    mutationFn: ({ id, body }: { id?: string; body: object }) =>
      platformApi.savePlan(id, body),
    onSuccess: async () => {
      setEditing(null);
      await client.invalidateQueries({ queryKey: ["plans"] });
    },
  });
  const plan = editing && editing !== "new" ? editing : undefined;
  return (
    <>
      <PageHeader
        eyebrow="Product catalogue"
        title="Plans"
        description="Manage packages and list prices. Existing agreed prices stay unchanged."
      />
      {actor?.role === "SUPER_ADMIN" && (
        <Button
          tone="primary"
          onClick={() => {
            save.reset();
            setEditing("new");
          }}
        >
          Create plan
        </Button>
      )}
      {actor?.role === "SUPER_ADMIN" &&
        plans.data &&
        !plans.data.some((p) => p.key === "WEBSITE_ONLY") && (
          <Button
            loading={addWebsite.isPending}
            onClick={() => addWebsite.mutate()}
          >
            Add Website-only plan
          </Button>
        )}
      {addWebsite.error && <p role="alert">{errorMessage(addWebsite.error)}</p>}
      {features.error && (
        <ErrorState
          error={errorMessage(features.error)}
          retry={() => void features.refetch()}
        />
      )}
      {editing && (
        <Panel title={plan ? `Edit ${plan.name}` : "New plan"}>
          <form
            className="platform-form"
            onSubmit={(e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              save.mutate({
                id: plan?.id,
                body: {
                  key: f.get("key"),
                  name: f.get("name"),
                  description: f.get("description"),
                  priceMinor: Math.round(Number(f.get("price")) * 100),
                  currency: f.get("currency"),
                  billingPeriod: f.get("billingPeriod"),
                  status: f.get("status"),
                  mediaQuotaBytes: Math.round(
                    Number(f.get("quotaMB")) * 1048576,
                  ),
                  mediaQuotaFiles: Number(f.get("quotaFiles")),
                  featureKeys: f.getAll("feature"),
                },
              });
            }}
            key={plan?.id ?? "new"}
          >
            <fieldset disabled={save.isPending || !features.data}>
              <div className="platform-form-grid">
                <Field label="Package key">
                  <Input
                    name="key"
                    required
                    pattern="[A-Za-z]([A-Za-z0-9_]|-)*"
                    defaultValue={plan?.key}
                  />
                </Field>
                <Field label="Customer-facing name">
                  <Input
                    name="name"
                    required
                    maxLength={100}
                    defaultValue={plan?.name}
                  />
                </Field>
              </div>
              <Field label="Description">
                <Input
                  name="description"
                  maxLength={2000}
                  defaultValue={plan?.description ?? ""}
                />
              </Field>
              <div className="platform-form-grid">
                <Field label="Price">
                  <Input
                    name="price"
                    type="number"
                    min={0}
                    max={1000000}
                    step="0.01"
                    required
                    defaultValue={(plan?.priceMinor ?? 0) / 100}
                  />
                </Field>
                <Field label="Currency">
                  <Input
                    name="currency"
                    required
                    pattern="[A-Z]{3}"
                    defaultValue={plan?.currency ?? "GEL"}
                  />
                </Field>
                <Field label="Billing period">
                  <Select
                    name="billingPeriod"
                    defaultValue={plan?.billingPeriod ?? "MONTH"}
                  >
                    <option value="MONTH">Monthly</option>
                    <option value="YEAR">Yearly</option>
                    <option value="ONE_TIME">One time</option>
                  </Select>
                </Field>
                <Field label="Availability">
                  <Select name="status" defaultValue={plan?.status ?? "ACTIVE"}>
                    <option value="ACTIVE">Active</option>
                    <option value="RETIRED">Retired</option>
                  </Select>
                </Field>
              </div>
              <div className="platform-form-grid">
                <Field label="Website storage (MB)">
                  <Input
                    name="quotaMB"
                    type="number"
                    min={0}
                    max={1024}
                    step="0.01"
                    required
                    defaultValue={(plan?.mediaQuotaBytes ?? 52428800) / 1048576}
                  />
                </Field>
                <Field label="Maximum photos">
                  <Input
                    name="quotaFiles"
                    type="number"
                    min={0}
                    max={1000}
                    required
                    defaultValue={plan?.mediaQuotaFiles ?? 50}
                  />
                </Field>
              </div>
              <fieldset>
                <legend>Included features</legend>
                {features.data
                  ?.filter((f) => f.key !== "NON_FISCAL_CLOSE")
                  .map((f) => (
                    <label key={f.key} className="platform-feature-row">
                      <input
                        type="checkbox"
                        name="feature"
                        value={f.key}
                        defaultChecked={plan?.features.some(
                          (p) => p.feature.key === f.key,
                        )}
                      />
                      {f.name}
                    </label>
                  ))}
              </fieldset>
              <p>
                Non-fiscal close is enabled only for a specific restaurant by an
                operator.
              </p>
              {save.error && <p role="alert">{errorMessage(save.error)}</p>}
              <Button type="submit" tone="primary" loading={save.isPending}>
                Save plan
              </Button>{" "}
              <Button onClick={() => setEditing(null)}>Cancel</Button>
            </fieldset>
          </form>
        </Panel>
      )}
      {plans.isPending ? (
        <LoadingState label="Loading plans" />
      ) : plans.error ? (
        <ErrorState
          error={errorMessage(plans.error)}
          retry={() => void plans.refetch()}
        />
      ) : (
        <div className="platform-card-grid">
          {plans.data.map((p) => (
            <Panel
              key={p.id}
              title={p.name}
              action={<StatusBadge value={p.status} />}
            >
              <p className="platform-mono">{p.key}</p>
              <p>{p.description}</p>
              <p>
                {((p.priceMinor ?? 0) / 100).toFixed(2)} {p.currency ?? "GEL"} /{" "}
                {p.billingPeriod ?? "MONTH"}
              </p>
              <div className="platform-chip-list">
                {p.features.map(({ feature }) => (
                  <span key={feature.key}>{feature.name}</span>
                ))}
              </div>
              {actor?.role === "SUPER_ADMIN" && (
                <Button
                  onClick={() => {
                    save.reset();
                    setEditing(p);
                  }}
                >
                  Edit plan
                </Button>
              )}
            </Panel>
          ))}
        </div>
      )}
    </>
  );
}
