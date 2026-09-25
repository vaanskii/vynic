import { commercialActions } from "../../../subscriptions/operator-actions";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { Button } from "../../components/Button";
import { Field, Input, Select } from "../../components/Form";
import { Panel } from "../../components/Page";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { LoadingState, ErrorState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";
import { errorMessage } from "../../format";
import {
  dateTime as day,
  remaining,
  money,
  type BillingQuote,
} from "../../../subscriptions/types";
import {
  WebsiteModeField,
  planHasWebsite,
} from "../../components/WebsiteModeField";

export function SubscriptionPanel({
  venueId,
  canEdit,
}: {
  venueId: string;
  canEdit: boolean;
}) {
  const client = useQueryClient();
  const subscription = useQuery({
    queryKey: ["subscription", venueId],
    queryFn: () => platformApi.subscription(venueId),
    refetchInterval: 60000,
  });
  const plans = useQuery({ queryKey: ["plans"], queryFn: platformApi.plans });
  const [action, setAction] = useState("");
  const [planId, setPlanId] = useState("");
  const [websiteMode, setWebsiteMode] = useState("");
  const product = useQuery({
    queryKey: ["product", venueId],
    queryFn: () => platformApi.product(venueId),
  });
  const [end, setEnd] = useState("");
  const [reason, setReason] = useState("");
  const [reference, setReference] = useState("");
  const [override, setOverride] = useState("");
  const [quote, setQuote] = useState<BillingQuote | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [feedback, setFeedback] = useState("");
  const refresh = async () => {
    await Promise.all(
      ["subscription", "product", "venue"].map((key) =>
        client.invalidateQueries({ queryKey: [key, venueId] }),
      ),
    );
  };
  const preview = useMutation({
    mutationFn: () =>
      platformApi.subscriptionQuote(venueId, {
        planId,
        reason,
        classification: override,
      }),
    onSuccess: (result) => {
      setQuote(result);
      setFeedback("");
    },
  });
  const save = useMutation({
    mutationFn: () =>
      quote?.kind === "SCHEDULE_CHANGE"
        ? platformApi.subscriptionAction(venueId, {
            action: "SCHEDULE_CHANGE",
            planId: quote.planId,
            reason,
            expectedPriceMinor: quote.priceMinor,
            expectedCurrency: quote.currency,
            expectedBillingPeriod: quote.billingPeriod,
            expectedVersion: quote.subscriptionVersion,
          })
        : quote
          ? platformApi.subscriptionPayment(venueId, {
              operationId: quote.id,
              reason,
              reference,
              confirm: true,
            })
          : platformApi.subscriptionAction(venueId, {
              action,
              planId,
              websiteMode:
                assignsWebsite && websiteMode ? websiteMode : undefined,
              trialEndsAt: end ? new Date(end).toISOString() : undefined,
              reason,
              classification: override,
              confirm: true,
            }),
    onSuccess: async () => {
      setConfirm(false);
      setAction("");
      setQuote(null);
      setReference("");
      setFeedback("Commercial access updated.");
      await refresh();
    },
  });
  if (subscription.isPending)
    return <LoadingState label="Loading subscription" />;
  if (subscription.error)
    return (
      <ErrorState
        error={errorMessage(subscription.error)}
        retry={() => void subscription.refetch()}
      />
    );
  const sub = subscription.data;
  const selected = plans.data?.find((plan) => plan.id === planId);
  const assignsWebsite =
    ["TRIAL", "GRANT_ACTIVE"].includes(action) && planHasWebsite(selected);
  const websiteSummary = assignsWebsite
    ? ` Website: ${websiteMode === "CUSTOM" ? "custom, operator-managed" : websiteMode === "SAAS" ? "Vynic SaaS" : "keep current implementation"}.`
    : "";
  const current = sub?.assignment;
  const currentMode = product.data?.website.configuredMode;
  const summary = quote
    ? quote.kind === "SCHEDULE_CHANGE"
      ? `${quote.planName} starts ${day(quote.effectiveAt)}. Current features remain until then. Renewal: ${money(quote.priceMinor, quote.currency)} / ${quote.billingPeriod.toLowerCase()}.`
      : `Confirm externally verified payment of ${money(quote.amountMinor, quote.currency)} for ${quote.planName}. ${quote.kind === "UPGRADE" ? `Renewal stays ${day(sub?.currentPeriodEndsAt)}.` : "The paid period begins on successful activation."}`
    : ["TRIAL", "EXTEND_TRIAL"].includes(action)
      ? `${selected?.name ?? current?.plan.name ?? "Selected plan"} Trial until ${day(end)}. Trial features are available immediately.${websiteSummary}`
      : action === "GRANT_ACTIVE"
        ? `Activate ${selected?.name ?? "selected plan"} now at ${money(selected?.priceMinor, selected?.currency)} per ${selected?.billingPeriod?.toLowerCase()}. This records a manual agreement, not a card payment.${websiteSummary}`
        : ["CANCEL_NOW", "END_TRIAL"].includes(action)
          ? "All commercial access ends now. Restaurant data and history are retained."
          : action === "SUSPEND"
            ? "Commercial access stops now. Local POS safe completion and settlement remain available."
            : action === "SCHEDULE_CHANGE"
              ? `${selected?.name ?? "Selected plan"} starts ${day(sub?.currentPeriodEndsAt)}. Current features remain until renewal.`
              : action === "SCHEDULE_CANCEL"
                ? `Access remains until ${day(sub?.currentPeriodEndsAt)}. No next renewal payment is due.`
                : action === "RESUME"
                  ? "Restore the current agreement only if its dates remain valid."
                  : "Remove the scheduled change and keep the current agreement.";
  const needsPlan = [
    "TRIAL",
    "GRANT_ACTIVE",
    "QUOTE",
    "SCHEDULE_CHANGE",
  ].includes(action);
  return (
    <Panel
      className="platform-subscription"
      title="Subscription"
      description="Current access, renewal and upcoming changes."
    >
      {feedback && (
        <p
          role="status"
          className="platform-feedback platform-feedback--success"
        >
          {feedback}
        </p>
      )}
      <StatusBadge value={sub?.status ?? "NO_PLAN"} />
      <h3>{current?.plan.name ?? "No package assigned"}</h3>
      <dl className="platform-subscription-facts">
        {sub?.status === "TRIAL" ? (
          <>
            <div>
              <dt>Trial started</dt>
              <dd>{day(sub.startedAt)}</dd>
            </div>
            <div>
              <dt>Trial ends</dt>
              <dd>{day(sub.trialEndsAt)}</dd>
            </div>
            <div>
              <dt>Remaining</dt>
              <dd>
                {remaining(
                  sub.trialEndsAt,
                  sub.serverTime
                    ? new Date(sub.serverTime).getTime()
                    : subscription.dataUpdatedAt,
                )}
              </dd>
            </div>
          </>
        ) : (
          <>
            <div>
              <dt>Agreed price</dt>
              <dd>
                {money(current?.agreedPriceMinor, current?.agreedCurrency)} /{" "}
                {current?.agreedBillingPeriod ?? "—"}
              </dd>
            </div>
            <div>
              <dt>Current period starts</dt>
              <dd>{day(sub?.currentPeriodStart)}</dd>
            </div>
            <div>
              <dt>Current period ends</dt>
              <dd>{day(sub?.currentPeriodEndsAt)}</dd>
            </div>
            <div>
              <dt>Next renewal</dt>
              <dd>
                {sub?.cancelAtPeriodEnd
                  ? "Cancellation scheduled"
                  : day(sub?.currentPeriodEndsAt)}
              </dd>
            </div>
          </>
        )}
      </dl>
      {sub?.pendingPlan && (
        <div className="platform-callout platform-subscription-next">
          <strong>Next: {sub.pendingPlan.name}</strong>
          <p>
            Starts {day(sub.pendingChangeAt)} ·{" "}
            {money(sub.pendingPriceMinor, sub.pendingCurrency)} /{" "}
            {sub.pendingBillingPeriod?.toLowerCase()}
          </p>
        </div>
      )}
      {sub?.cancelAtPeriodEnd && (
        <p className="platform-callout">
          Cancels {day(sub.currentPeriodEndsAt)}. Current features remain until
          then.
        </p>
      )}
      {!sub?.billingManaged && sub?.status === "ACTIVE" && (
        <p>
          Legacy manual agreement. Confirm billing terms before starting a
          renewal schedule.
        </p>
      )}
      {canEdit && (
        <form
          className="platform-form"
          onSubmit={(e) => {
            e.preventDefault();
            save.reset();
            preview.reset();
            setFeedback("");
            if (action === "QUOTE") preview.mutate();
            else {
              setQuote(null);
              setConfirm(true);
            }
          }}
        >
          <Field label="Commercial action">
            <Select
              required
              value={action}
              onChange={(e) => {
                const next = e.target.value;
                setAction(next);
                if (["TRIAL", "EXTEND_TRIAL"].includes(next)) {
                  const date = new Date(
                    next === "EXTEND_TRIAL" && sub?.trialEndsAt
                      ? sub.trialEndsAt
                      : subscription.dataUpdatedAt,
                  );
                  date.setDate(
                    date.getDate() + (next === "EXTEND_TRIAL" ? 7 : 14),
                  );
                  setEnd(
                    new Date(date.getTime() - date.getTimezoneOffset() * 60000)
                      .toISOString()
                      .slice(0, 16),
                  );
                }
                setQuote(null);
                save.reset();
                preview.reset();
              }}
            >
              <option value="">Choose action</option>
              {commercialActions(
                sub?.status ?? "NO_PLAN",
                !!sub?.billingManaged,
              ).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
              {sub?.pendingPlan && (
                <option value="CANCEL_CHANGE">Cancel scheduled change</option>
              )}
              {sub?.cancelAtPeriodEnd && (
                <option value="UNDO_CANCEL">
                  Keep subscription at renewal
                </option>
              )}
            </Select>
          </Field>
          {needsPlan && (
            <Field label="Plan">
              <Select
                required
                value={planId}
                onChange={(e) => {
                  setPlanId(e.target.value);
                  setQuote(null);
                }}
              >
                <option value="">Choose plan</option>
                {plans.data
                  ?.filter(
                    (p) => p.status === "ACTIVE" || p.id === current?.planId,
                  )
                  .map((p) => (
                    <option value={p.id} key={p.id}>
                      {p.name} · {money(p.priceMinor, p.currency)}
                    </option>
                  ))}
              </Select>
            </Field>
          )}
          {plans.error && (
            <ErrorState
              error={errorMessage(plans.error)}
              retry={() => void plans.refetch()}
            />
          )}
          {assignsWebsite && (
            <WebsiteModeField
              current={currentMode}
              value={websiteMode}
              onChange={setWebsiteMode}
            />
          )}
          {["TRIAL", "EXTEND_TRIAL"].includes(action) && (
            <Field label="Trial end date and time (local timezone)">
              <Input
                type="datetime-local"
                required
                value={end}
                onChange={(e) => setEnd(e.target.value)}
              />
            </Field>
          )}
          {["QUOTE", "SCHEDULE_CHANGE"].includes(action) && (
            <Field label="Mixed-package review">
              <Select
                value={override}
                onChange={(e) => setOverride(e.target.value)}
              >
                <option value="">Use feature and price rules</option>
                <option value="UPGRADE">Explicit immediate upgrade</option>
                <option value="RENEWAL_CHANGE">
                  Explicit change at renewal
                </option>
              </Select>
            </Field>
          )}
          <Field label="Operator reason">
            <Input
              required
              maxLength={1000}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </Field>
          <Button
            type="submit"
            loading={preview.isPending}
            tone={
              ["CANCEL_NOW", "END_TRIAL"].includes(action)
                ? "danger"
                : "primary"
            }
          >
            {action === "QUOTE" ? "Calculate quote" : "Review change"}
          </Button>
        </form>
      )}
      {preview.error && <p role="alert">{errorMessage(preview.error)}</p>}
      {canEdit && quote && (
        <div className="platform-callout">
          <div>
            <h3>{quote.planName}</h3>
            <p>{summary}</p>
            {quote.expiresAt && (
              <p>
                Quote expires {new Date(quote.expiresAt).toLocaleTimeString()}.
              </p>
            )}
            {quote.kind !== "SCHEDULE_CHANGE" && (
              <Field label="External payment reference">
                <Input
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                  maxLength={200}
                />
              </Field>
            )}
            <Button
              disabled={quote.kind !== "SCHEDULE_CHANGE" && !reference.trim()}
              onClick={() => {
                save.reset();
                setConfirm(true);
              }}
            >
              {quote.kind === "SCHEDULE_CHANGE"
                ? "Review scheduled change"
                : "Confirm manual payment…"}
            </Button>
          </div>
        </div>
      )}
      {canEdit && !!sub?.operations?.length && !quote && (
        <details>
          <summary>Pending payment quotes</summary>
          {sub.operations.map((op) => (
            <p key={op.id}>
              {op.planName} · {money(op.amountMinor, op.currency)}{" "}
              <Button
                onClick={() => {
                  setQuote(op);
                  setAction("QUOTE");
                }}
              >
                Review payment
              </Button>
            </p>
          ))}
        </details>
      )}
      <details>
        <summary>Commercial history</summary>
        {sub?.history?.length ? (
          <ol>
            {sub.history.map((item) => (
              <li key={item.id}>
                {day(item.createdAt)} ·{" "}
                {item.action
                  .replace(/^subscription\.|^venue\./, "")
                  .replaceAll("_", " ")}
                {typeof item.metadata?.reason === "string" &&
                  ` — ${item.metadata.reason}`}
              </li>
            ))}
          </ol>
        ) : (
          <p>No lifecycle events yet.</p>
        )}
      </details>
      <ConfirmDialog
        open={confirm}
        onOpenChange={(open) => {
          if (!save.isPending) setConfirm(open);
        }}
        title="Confirm commercial change"
        description={summary}
        confirmLabel={
          quote && quote.kind !== "SCHEDULE_CHANGE"
            ? "Record verified payment"
            : "Apply change"
        }
        danger={["CANCEL_NOW", "END_TRIAL", "SUSPEND"].includes(action)}
        pending={save.isPending}
        error={save.error ? errorMessage(save.error) : undefined}
        onConfirm={() => save.mutate()}
      />
    </Panel>
  );
}
