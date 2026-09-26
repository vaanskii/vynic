import { useState } from "react";
import {
  ArrowSquareOut,
  CheckCircle,
  WarningCircle,
} from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage, formatDateTime } from "../../format";
import type { CustomWebsite, CustomWebsiteCheck } from "../../types";
import { Button } from "../../components/Button";
import { Field, FormError, Input, Select } from "../../components/Form";
import { Panel } from "../../components/Page";
import { ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";

type SettableStatus = Exclude<CustomWebsite["status"], "NOT_CONFIGURED">;

const statusLabels: Record<SettableStatus, string> = {
  SETUP_PENDING: "Setup pending — frontend in development",
  READY: "Ready — deployed and verified, not launched",
  ACTIVE: "Active — live for visitors",
  ERROR: "Error — deployment or domain problem",
};

const checkLabels: Record<keyof CustomWebsite["readiness"]["checks"], string> =
  {
    entitled: "WEBSITE access is effective",
    customMode: "Website mode is CUSTOM",
    siteKey: "Custom frontend identity recorded",
    activeDomain: "At least one active domain",
  };

const capabilityLabels: Record<keyof CustomWebsite["capabilities"], string> = {
  profile: "Restaurant profile",
  menu: "Menu",
  customerAccounts: "Website customer accounts",
  onlinePayments: "Online payments (BOG)",
  reservations: "Paid reservations",
};

const auditLabels: Record<string, string> = {
  "venue.website_mode_changed": "Website mode changed",
  "venue.custom_website_site_key_changed": "Frontend identity changed",
  "venue.custom_website_status_changed": "Setup status changed",
  "venue.domain_registered": "Domain registered",
  "venue.domain_status_changed": "Domain status changed",
  "venue.domain_released": "Domain released",
  "venue.feature_override_set": "Feature override set",
  "venue.feature_override_removed": "Feature override removed",
  "venue.cloud_menu_enabled": "Dashboard menu editing enabled",
  "venue.cloud_menu_disabled": "Dashboard menu editing disabled",
};

const apiLabels: Record<CustomWebsiteCheck["api"]["state"], string> = {
  OK: "Answers for this Venue",
  WRONG_SITE: "Answers for a different restaurant",
  FAILED: "Not answering",
  NOT_CHECKED: "Not checked",
};

/**
 * Operator provisioning for a CUSTOM website.
 *
 * Records which custom frontend serves the Venue and how far its setup has got.
 * Nothing here deploys a frontend or touches DNS/TLS: READY and ACTIVE are
 * operator attestations, gated by a server-side checklist.
 */
export function CustomWebsitePanel({ venueId }: { venueId: string }) {
  const queryClient = useQueryClient();
  const custom = useQuery({
    queryKey: ["custom-website", venueId],
    queryFn: () => platformApi.customWebsite(venueId),
  });
  const [siteKey, setSiteKey] = useState<string | null>(null);
  const [status, setStatus] = useState<SettableStatus | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  // Held only for this view: availability is observed, never stored.
  const [check, setCheck] = useState<CustomWebsiteCheck | null>(null);
  const runCheck = useMutation({
    mutationFn: () => platformApi.checkCustomWebsite(venueId),
    onSuccess: setCheck,
  });
  const save = useMutation({
    mutationFn: (body: Parameters<typeof platformApi.updateCustomWebsite>[1]) =>
      platformApi.updateCustomWebsite(venueId, body),
    onSuccess: async (next) => {
      queryClient.setQueryData(["custom-website", venueId], next);
      await queryClient.invalidateQueries({ queryKey: ["audit"] });
      setSiteKey(null);
      setStatus(null);
      setNote(null);
      setSaved(true);
    },
  });

  if (custom.isPending)
    return <LoadingState label="Loading custom website setup" />;
  if (custom.isError)
    return (
      <ErrorState
        error={errorMessage(custom.error)}
        retry={() => void custom.refetch()}
      />
    );
  const data = custom.data;
  const currentStatus: SettableStatus =
    data.status === "NOT_CONFIGURED" ? "SETUP_PENDING" : data.status;
  const draft = {
    siteKey: siteKey ?? data.siteKey ?? "",
    status: status ?? currentStatus,
    note: note ?? data.statusNote ?? "",
  };
  const changes: Parameters<typeof platformApi.updateCustomWebsite>[1] = {};
  if (draft.siteKey !== (data.siteKey ?? ""))
    changes.siteKey = draft.siteKey || null;
  if (draft.status !== data.status) changes.status = draft.status;
  if (draft.note !== (data.statusNote ?? ""))
    changes.statusNote = draft.note || null;
  const dirty = Object.keys(changes).length > 0;

  return (
    <>
      <Panel
        title="Custom website"
        description="A bespoke frontend over the shared Vynic backend. The Host still decides the Venue; the frontend identity only records which build should serve these domains."
      >
        <div className="platform-website-state">
          <div>
            <span>Setup status</span>
            <StatusBadge value={data.status} />
          </div>
          <div>
            <span>Frontend identity</span>
            <span>{data.siteKey ?? "Not recorded"}</span>
          </div>
          <div>
            <span>Primary domain</span>
            <span>{data.primaryDomain ?? "No active domain"}</span>
          </div>
          <div>
            <span>Website access</span>
            <span>
              <StatusBadge value={data.entitled ? "ENABLED" : "DISABLED"}>
                {data.entitled ? "Effective" : "Not effective"}
              </StatusBadge>{" "}
              {data.commercialStatus}
              {data.trialEndsAt
                ? ` · Trial ends ${formatDateTime(data.trialEndsAt)}`
                : ""}
            </span>
          </div>
          <div>
            <span>Online payments</span>
            <StatusBadge value={data.payments} />
          </div>
        </div>
        <ul className="platform-checklist" aria-label="Readiness">
          {(Object.keys(checkLabels) as Array<keyof typeof checkLabels>).map(
            (key) => (
              <li key={key}>
                {data.readiness.checks[key] ? (
                  <CheckCircle size={16} weight="fill" aria-label="done" />
                ) : (
                  <WarningCircle size={16} aria-label="missing" />
                )}{" "}
                {checkLabels[key]}
              </li>
            ),
          )}
        </ul>
        <form
          className="platform-form"
          onSubmit={(event) => {
            event.preventDefault();
            setSaved(false);
            if (dirty) save.mutate(changes);
          }}
        >
          <Field
            label="Custom frontend identity"
            hint="Lowercase app key, e.g. vankisi-web or restaurant-x-web. The frontend checks it against its build."
          >
            <Input
              value={draft.siteKey}
              onChange={(event) => setSiteKey(event.target.value.trim())}
              maxLength={64}
              pattern="[a-z0-9][a-z0-9-]{0,62}[a-z0-9]"
            />
          </Field>
          <Field
            label="Setup status"
            hint="Tracking only. READY and ACTIVE require every readiness item."
          >
            <Select
              value={draft.status}
              onChange={(event) =>
                setStatus(event.target.value as SettableStatus)
              }
            >
              {(Object.keys(statusLabels) as SettableStatus[]).map((key) => (
                <option key={key} value={key}>
                  {statusLabels[key]}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Operator note" hint="Internal; never shown publicly.">
            <Input
              value={draft.note}
              onChange={(event) => setNote(event.target.value)}
              maxLength={500}
            />
          </Field>
          <FormError>
            {save.error ? errorMessage(save.error) : undefined}
          </FormError>
          {saved && !dirty ? (
            <p role="status">Custom website setup saved.</p>
          ) : null}
          <div>
            <Button
              tone="primary"
              type="submit"
              disabled={!dirty || save.isPending}
            >
              Save custom setup
            </Button>
          </div>
        </form>
      </Panel>
      <div className="platform-grid platform-grid--2 platform-section-gap">
        <Panel
          title="Live site"
          description="Whether the site answers right now. Checked on demand from the server against the primary domain; not stored, not monitored, and independent of the setup status above."
        >
          <div className="platform-website-state">
            <div>
              <span>Public URL</span>
              <span>{data.publicUrl ?? "Register an active domain first"}</span>
            </div>
            <div>
              <span>Runtime availability</span>
              <StatusBadge value={check?.availability ?? "UNKNOWN"} />
            </div>
            {check ? (
              <>
                <div>
                  <span>Frontend</span>
                  <span>{check.frontend.detail}</span>
                </div>
                <div>
                  <span>Backend through this domain</span>
                  <span>
                    {apiLabels[check.api.state]}
                    {check.api.state === "OK" ? "" : ` · ${check.api.detail}`}
                  </span>
                </div>
              </>
            ) : null}
            <div>
              <span>Last checked</span>
              <span>
                {check ? formatDateTime(check.checkedAt) : "Not checked yet"}
              </span>
            </div>
          </div>
          <div className="platform-inline-actions">
            {data.publicUrl ? (
              <a
                className="platform-button platform-button--secondary"
                href={data.publicUrl}
                target="_blank"
                rel="noreferrer"
              >
                <ArrowSquareOut size={14} aria-hidden="true" />
                Open website
              </a>
            ) : (
              <Button disabled>Open website</Button>
            )}
            <Button
              tone="primary"
              disabled={!data.primaryDomain}
              loading={runCheck.isPending}
              loadingLabel="Checking…"
              onClick={() => runCheck.mutate()}
            >
              Check now
            </Button>
          </div>
          <FormError>
            {runCheck.error ? errorMessage(runCheck.error) : undefined}
          </FormError>
        </Panel>
        <Panel
          title="Menu"
          description="The same canonical restaurant catalog as SAAS. The custom frontend only decides how it looks; the package decides who edits it."
        >
          <div className="platform-website-state">
            <div>
              <span>Menu authority</span>
              <StatusBadge value={data.menu.authority}>
                {data.menu.authority === "CLOUD"
                  ? "Cloud (owner Dashboard)"
                  : "POS"}
              </StatusBadge>
            </div>
            <div>
              <span>Dashboard menu editing</span>
              <StatusBadge
                value={data.menu.editingEnabled ? "ENABLED" : "DISABLED"}
              />
            </div>
          </div>
          {data.menu.needsCloudAuthority ? (
            <p
              className="platform-feedback platform-feedback--warning"
              role="alert"
            >
              Website-only package, but the menu is still on POS authority, so
              nobody can edit it. Enable Dashboard menu editing in Product to
              move it to the Cloud catalog.
            </p>
          ) : null}
        </Panel>
      </div>
      <div className="platform-grid platform-grid--2 platform-section-gap">
        <Panel
          title="Shared capabilities"
          description="Derived from effective features and configured data; change them in Product access and payments."
        >
          <ul className="platform-checklist">
            {(
              Object.keys(capabilityLabels) as Array<
                keyof typeof capabilityLabels
              >
            ).map((key) => (
              <li key={key}>
                <StatusBadge
                  value={data.capabilities[key] ? "ENABLED" : "DISABLED"}
                />{" "}
                {capabilityLabels[key]}
              </li>
            ))}
          </ul>
        </Panel>
        <Panel title="Custom website history">
          {data.audit.length === 0 ? (
            <p>No custom website changes recorded yet.</p>
          ) : (
            <ul className="platform-checklist">
              {data.audit.map((event) => (
                <li key={event.id}>
                  <strong>{auditLabels[event.action] ?? event.action}</strong> ·{" "}
                  {event.actor} · {formatDateTime(event.createdAt)}
                  {event.metadata &&
                  ("from" in event.metadata || "hostname" in event.metadata)
                    ? ` · ${
                        "hostname" in event.metadata
                          ? String(event.metadata.hostname)
                          : "enabled" in event.metadata
                            ? event.metadata.enabled
                              ? `menu ${String(event.metadata.from ?? "—")} → CLOUD`
                              : "menu editing off"
                            : `${String(event.metadata.from ?? "—")} → ${String(event.metadata.to ?? "—")}`
                      }`
                    : ""}
                </li>
              ))}
            </ul>
          )}
        </Panel>
      </div>
    </>
  );
}
