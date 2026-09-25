import { SubscriptionPanel } from "./SubscriptionPanel";
import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { useAuth } from "../../auth";
import type { ManagerAccess } from "../../types";
import { errorMessage, formatRelativeTime } from "../../format";
import { Button } from "../../components/Button";
import { Field, Input, Select, FormError } from "../../components/Form";
import { Panel } from "../../components/Page";
import { Dialog } from "../../components/Dialog";
import { ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";

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
  const managers = useQuery({
    queryKey: ["managers", venueId],
    queryFn: () => platformApi.managers(venueId),
    refetchInterval: 15000,
    enabled: showAccess,
  });
  const awaitingDelivery =
    managers.data?.some(
      (staff) =>
        staff.delivery &&
        ["PENDING", "CLAIMED"].includes(staff.delivery.status),
    ) ?? false;
  const devices = useQuery({
    queryKey: ["devices", venueId],
    queryFn: () => platformApi.devices(venueId),
    enabled: showAccess && awaitingDelivery,
    refetchInterval: 15000,
  });
  const primary = devices.data?.find((device) => device.isOperationalPrimary);
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
  if (showAccess && managers.isPending)
    return <LoadingState label="Loading Manager access" />;
  if (showAccess && managers.error)
    return (
      <ErrorState
        error={errorMessage(managers.error)}
        retry={() => void managers.refetch()}
      />
    );
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
      {!accessOnly && <SubscriptionPanel venueId={venueId} canEdit={canEdit} />}
      {showAccess && (
        <Panel
          title="Manager access"
          description="რესტორნის კოდი შეიყვანეთ ერთხელ, შემდეგ გამოიყენეთ პირადი PIN. POS-ზე PIN განახლდება მთავარ ტერმინალთან სინქრონიზაციის შემდეგ."
        >
          {canEdit && (
            <Button tone="primary" onClick={() => openAccess("create")}>
              Create Manager
            </Button>
          )}
          {awaitingDelivery && (
            <div className="platform-callout" role="status">
              <div>
                <strong>POS access is waiting for the Primary POS.</strong>
                <p>
                  Connecting another terminal does not make it Primary. If this
                  is a replacement, select it explicitly under Devices after
                  stopping the previous POS and checking the restaurant data.
                </p>
                {devices.isPending ? (
                  <LoadingState label="Checking Primary POS" />
                ) : devices.error ? (
                  <ErrorState
                    error={errorMessage(devices.error)}
                    retry={() => void devices.refetch()}
                  />
                ) : (
                  <p>
                    {primary
                      ? `Primary: ${primary.displayName} (${primary.id.slice(0, 8)}). ${primary.lastSeenAt ? formatRelativeTime(primary.lastSeenAt) : "Never connected"}.`
                      : "No Primary POS is selected."}
                  </p>
                )}
                <div className="platform-page-header__actions">
                  <Link
                    className="platform-button platform-button--quiet"
                    to={`/venues/${venueId}/devices`}
                  >
                    Review POS devices
                  </Link>
                  <Button
                    loading={managers.isFetching || devices.isFetching}
                    loadingLabel="Checking delivery…"
                    onClick={() => {
                      void managers.refetch();
                      void devices.refetch();
                    }}
                  >
                    Check delivery
                  </Button>
                </div>
              </div>
            </div>
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
                          : staff.delivery.status === "CLAIMED"
                            ? "Applying on Primary POS…"
                            : "Waiting for Primary POS"}
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
      <Dialog
        open={access !== null}
        onOpenChange={(open) => {
          if (!open && !changeAccess.isPending) {
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
              disabled={changeAccess.isPending}
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
              loading={changeAccess.isPending}
              loadingLabel="Saving access…"
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
            if (!changeAccess.isPending) changeAccess.mutate();
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
