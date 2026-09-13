import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { useAuth } from "../../auth";
import type { ManagerAccess, SubscriptionStatus } from "../../types";
import { errorMessage, formatDateTime } from "../../format";
import { Button } from "../../components/Button";
import { Field, Input, Select, FormError } from "../../components/Form";
import { Panel } from "../../components/Page";
import { Dialog } from "../../components/Dialog";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";

const actions: [SubscriptionStatus, string][] = [
  ["TRIAL", "Start trial"],
  ["ACTIVE", "Activate / Reactivate"],
  ["PAST_DUE", "Mark past due"],
  ["SUSPENDED", "Suspend"],
  ["CANCELLED", "Cancel subscription"],
];
export function VenueCommercialTab({
  venueId,
  accessOnly = false,
  showAccess = true,
}: {
  venueId: string;
  accessOnly?: boolean;
  showAccess?: boolean;
}) {
  const { actor } = useAuth();
  const canEdit = actor?.role === "SUPER_ADMIN";
  const client = useQueryClient();
  const subscription = useQuery({
    queryKey: ["subscription", venueId],
    queryFn: () => platformApi.subscription(venueId),
    enabled: !accessOnly,
  });
  const managers = useQuery({
    queryKey: ["managers", venueId],
    queryFn: () => platformApi.managers(venueId),
    refetchInterval: 15000,
    enabled: showAccess,
  });
  const [nextStatus, setNextStatus] = useState<SubscriptionStatus | null>(null);
  const [note, setNote] = useState("");
  const [trialEndsAt, setTrialEndsAt] = useState("");
  const [currentPeriodEndsAt, setCurrentPeriodEndsAt] = useState("");
  useEffect(() => {
    setNote(subscription.data?.note ?? "");
    setTrialEndsAt(subscription.data?.trialEndsAt?.slice(0, 10) ?? "");
    setCurrentPeriodEndsAt(
      subscription.data?.currentPeriodEndsAt?.slice(0, 10) ?? "",
    );
  }, [subscription.data]);
  const [access, setAccess] = useState<{
    action: "create" | "reset" | "disable";
    staff?: ManagerAccess;
    requestId: string;
  } | null>(null);
  const [form, setForm] = useState({
    displayName: "",
    username: "",
    role: "MANAGER",
    pin: "",
  });
  const [feedback, setFeedback] = useState("");
  const changeSubscription = useMutation({
    mutationFn: () =>
      platformApi.setSubscription(venueId, {
        status: nextStatus!,
        note,
        trialEndsAt: trialEndsAt || null,
        currentPeriodEndsAt: currentPeriodEndsAt || null,
      }),
    onSuccess: async () => {
      setNextStatus(null);
      await client.invalidateQueries({ queryKey: ["subscription", venueId] });
      await client.invalidateQueries({ queryKey: ["product", venueId] });
      setFeedback("Subscription updated.");
    },
  });
  const changeAccess = useMutation({
    mutationFn: () =>
      platformApi.managerAccess(
        venueId,
        access!.action,
        { ...form, requestId: access!.requestId },
        access!.staff?.id,
      ),
    onSuccess: async (result) => {
      setAccess(null);
      setForm({ displayName: "", username: "", role: "MANAGER", pin: "" });
      await client.invalidateQueries({ queryKey: ["managers", venueId] });
      setFeedback(
        `Manager access saved. POS delivery: ${result.delivery.status.toLowerCase()}.`,
      );
    },
  });
  const openAccess = (
    action: "create" | "reset" | "disable",
    staff?: ManagerAccess,
  ) => {
    changeAccess.reset();
    setForm({ displayName: "", username: "", role: "MANAGER", pin: "" });
    setAccess({ action, staff, requestId: crypto.randomUUID() });
  };
  if (
    (!accessOnly && subscription.isPending) ||
    (showAccess && managers.isPending)
  )
    return <LoadingState label="Loading commercial access" />;
  if ((!accessOnly && subscription.error) || (showAccess && managers.error))
    return (
      <ErrorState
        error={errorMessage(
          (!accessOnly && subscription.error) || managers.error,
        )}
        retry={() => {
          void subscription.refetch();
          void managers.refetch();
        }}
      />
    );
  const current = subscription.data;
  return (
    <>
      {feedback && (
        <p
          role="status"
          className="platform-feedback platform-feedback--success"
        >
          {feedback}
        </p>
      )}
      {!accessOnly && (
        <Panel
          title="Subscription"
          description="Controls Manager and Website access. Past due retains access during a manually managed grace period."
        >
          <StatusBadge value={current?.status ?? "ACTIVE"} />
          <dl>
            <dt>Started</dt>
            <dd>
              {current?.startedAt ? formatDateTime(current.startedAt) : "—"}
            </dd>
            <dt>Trial ends</dt>
            <dd>
              {current?.trialEndsAt ? formatDateTime(current.trialEndsAt) : "—"}
            </dd>
            <dt>Current period ends</dt>
            <dd>
              {current?.currentPeriodEndsAt
                ? formatDateTime(current.currentPeriodEndsAt)
                : "—"}
            </dd>
            <dt>Note</dt>
            <dd>{current?.note || "—"}</dd>
          </dl>
          {canEdit && (
            <div className="platform-form">
              <Field label="Operator note">
                <Input
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  maxLength={1000}
                />
              </Field>
              <div className="platform-form-grid">
                <Field label="Trial end date">
                  <Input
                    type="date"
                    value={trialEndsAt}
                    onChange={(e) => setTrialEndsAt(e.target.value)}
                  />
                </Field>
                <Field label="Current period end date">
                  <Input
                    type="date"
                    value={currentPeriodEndsAt}
                    onChange={(e) => setCurrentPeriodEndsAt(e.target.value)}
                  />
                </Field>
              </div>
              <div className="platform-feature-actions">
                {actions.map(([status, label]) => (
                  <Button
                    key={status}
                    tone={
                      status === "SUSPENDED" || status === "CANCELLED"
                        ? "danger"
                        : "secondary"
                    }
                    onClick={() => {
                      changeSubscription.reset();
                      setNextStatus(status);
                    }}
                  >
                    {label}
                  </Button>
                ))}
              </div>
            </div>
          )}
        </Panel>
      )}
      {showAccess && (
        <Panel
          title="Manager access"
          description="რესტორნის კოდი შეიყვანეთ ერთხელ, შემდეგ გამოიყენეთ პირადი PIN. POS-ზე წვდომა განახლდება ტერმინალის დაკავშირებისას."
        >
          {canEdit && (
            <Button tone="primary" onClick={() => openAccess("create")}>
              Create Manager
            </Button>
          )}
          {!managers.data?.length && <p>No Manager accounts yet.</p>}
          <div className="platform-feature-list">
            {managers.data?.map((staff) => (
              <article className="platform-feature-row" key={staff.id}>
                <div className="platform-feature-row__copy">
                  <strong>{staff.displayName || staff.username}</strong>
                  <p>
                    {staff.username} · {staff.role}
                  </p>
                  {staff.delivery && (
                    <p>
                      POS:{" "}
                      {staff.delivery.status === "SUCCEEDED"
                        ? "Applied"
                        : staff.delivery.status === "FAILED"
                          ? `Failed (${staff.delivery.resultCode ?? "unknown"}). Reset access to retry.`
                          : "Waiting for terminal"}
                    </p>
                  )}
                </div>
                <StatusBadge value={staff.isActive ? "ACTIVE" : "DISABLED"} />
                {canEdit && (
                  <div className="platform-feature-actions">
                    <Button onClick={() => openAccess("reset", staff)}>
                      Reset PIN / Reactivate
                    </Button>
                    <Button
                      tone="danger"
                      disabled={!staff.isActive}
                      onClick={() => openAccess("disable", staff)}
                    >
                      Disable access
                    </Button>
                  </div>
                )}
              </article>
            ))}
          </div>
        </Panel>
      )}
      <ConfirmDialog
        open={nextStatus !== null}
        onOpenChange={(open) => {
          if (!open) setNextStatus(null);
        }}
        title={`Set subscription to ${nextStatus}?`}
        description="Suspended and cancelled subscriptions deny Manager and Website access. Local POS checkout, printing and day close continue."
        confirmLabel="Update subscription"
        danger={nextStatus === "SUSPENDED" || nextStatus === "CANCELLED"}
        pending={changeSubscription.isPending}
        error={
          changeSubscription.error
            ? errorMessage(changeSubscription.error)
            : undefined
        }
        onConfirm={() => changeSubscription.mutate()}
      />
      <Dialog
        open={access !== null}
        onOpenChange={(open) => {
          if (!open) {
            setAccess(null);
            setForm({ ...form, pin: "" });
          }
        }}
        title={
          access?.action === "create"
            ? "Create Manager"
            : access?.action === "reset"
              ? `Reset access for ${access.staff?.username}`
              : `Disable ${access?.staff?.username}?`
        }
        description={
          access?.action === "disable"
            ? "Manager sessions stop on the next request. History is retained."
            : "PIN must be 4–6 digits. It will not be displayed after saving."
        }
        footer={
          <>
            <Button
              onClick={() => {
                setAccess(null);
                setForm({ ...form, pin: "" });
              }}
            >
              Cancel
            </Button>
            <Button
              tone={access?.action === "disable" ? "danger" : "primary"}
              type="submit"
              form="manager-access"
              disabled={changeAccess.isPending}
            >
              Save access
            </Button>
          </>
        }
      >
        <form
          id="manager-access"
          className="platform-form"
          onSubmit={(e) => {
            e.preventDefault();
            changeAccess.mutate();
          }}
        >
          {access?.action === "create" && (
            <>
              <Field label="Display name">
                <Input
                  required
                  value={form.displayName}
                  onChange={(e) =>
                    setForm({ ...form, displayName: e.target.value })
                  }
                />
              </Field>
              <Field label="Username">
                <Input
                  required
                  value={form.username}
                  onChange={(e) =>
                    setForm({ ...form, username: e.target.value })
                  }
                />
              </Field>
              <Field label="Role">
                <Select
                  value={form.role}
                  onChange={(e) => setForm({ ...form, role: e.target.value })}
                >
                  <option value="MANAGER">Manager</option>
                  <option value="ADMIN">Admin</option>
                </Select>
              </Field>
            </>
          )}
          {access?.action !== "disable" && (
            <Field label="New PIN">
              <Input
                required
                type="password"
                autoComplete="new-password"
                inputMode="numeric"
                pattern="[0-9]{4,6}"
                minLength={4}
                maxLength={6}
                value={form.pin}
                onChange={(e) => setForm({ ...form, pin: e.target.value })}
              />
            </Field>
          )}
          <FormError>
            {changeAccess.error ? errorMessage(changeAccess.error) : undefined}
          </FormError>
        </form>
      </Dialog>
    </>
  );
}
