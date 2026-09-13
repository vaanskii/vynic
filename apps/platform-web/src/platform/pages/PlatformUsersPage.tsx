import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../api";
import { useAuth } from "../auth";
import { errorMessage } from "../format";
import { Button } from "../components/Button";
import { Field, Input, Select, FormError } from "../components/Form";
import { PageHeader, Panel } from "../components/Page";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { StatusBadge } from "../components/StatusBadge";
import { ErrorState, LoadingState } from "../components/State";
export function PlatformUsersPage() {
  const { actor } = useAuth();
  const client = useQueryClient();
  const users = useQuery({
    queryKey: ["platform-users"],
    queryFn: platformApi.users,
  });
  const [form, setForm] = useState({
    email: "",
    displayName: "",
    password: "",
    role: "SUPPORT_READONLY",
  });
  const [disableId, setDisableId] = useState<string | null>(null);
  const [feedback, setFeedback] = useState("");
  const create = useMutation({
    mutationFn: () => platformApi.createUser(form),
    onSuccess: async () => {
      setForm({
        email: "",
        displayName: "",
        password: "",
        role: "SUPPORT_READONLY",
      });
      setFeedback(
        "Platform user created. Share their password through your secure channel.",
      );
      await client.invalidateQueries({ queryKey: ["platform-users"] });
    },
  });
  const disable = useMutation({
    mutationFn: () => platformApi.disableUser(disableId!),
    onSuccess: async () => {
      setDisableId(null);
      await client.invalidateQueries({ queryKey: ["platform-users"] });
    },
  });
  if (users.isPending) return <LoadingState label="Loading Platform users" />;
  if (users.error)
    return (
      <ErrorState
        error={errorMessage(users.error)}
        retry={() => void users.refetch()}
      />
    );
  return (
    <>
      <PageHeader
        title="Platform users"
        description="Vynic operator accounts. Support can inspect data but cannot make changes."
      />
      {feedback && <p role="status">{feedback}</p>}
      <Panel title="Accounts">
        <div className="platform-feature-list">
          {users.data.map((user) => (
            <article className="platform-feature-row" key={user.id}>
              <div className="platform-feature-row__copy">
                <strong>{user.displayName}</strong>
                <p>
                  {user.email} ·{" "}
                  {user.role === "SUPER_ADMIN"
                    ? "Super admin"
                    : "Support (read only)"}
                </p>
              </div>
              <StatusBadge value={user.status} />
              {actor?.role === "SUPER_ADMIN" && (
                <Button
                  tone="danger"
                  disabled={
                    user.id === actor.platformUserId ||
                    user.status === "DISABLED"
                  }
                  onClick={() => setDisableId(user.id)}
                >
                  Disable
                </Button>
              )}
            </article>
          ))}
        </div>
      </Panel>
      {actor?.role === "SUPER_ADMIN" && (
        <Panel title="Create Platform user">
          <form
            className="platform-form"
            onSubmit={(e) => {
              e.preventDefault();
              create.mutate();
            }}
          >
            <Field label="Display name">
              <Input
                required
                value={form.displayName}
                onChange={(e) =>
                  setForm({ ...form, displayName: e.target.value })
                }
              />
            </Field>
            <Field label="Email">
              <Input
                type="email"
                required
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
              />
            </Field>
            <Field label="Role">
              <Select
                value={form.role}
                onChange={(e) => setForm({ ...form, role: e.target.value })}
              >
                <option value="SUPPORT_READONLY">Support (read only)</option>
                <option value="SUPER_ADMIN">Super admin</option>
              </Select>
            </Field>
            <Field label="Initial password (at least 12 characters)">
              <Input
                type="password"
                autoComplete="new-password"
                required
                minLength={12}
                value={form.password}
                onChange={(e) => setForm({ ...form, password: e.target.value })}
              />
            </Field>
            <FormError>
              {create.error ? errorMessage(create.error) : undefined}
            </FormError>
            <Button type="submit" tone="primary" disabled={create.isPending}>
              Create user
            </Button>
          </form>
        </Panel>
      )}
      <ConfirmDialog
        open={disableId !== null}
        onOpenChange={(open) => {
          if (!open) setDisableId(null);
        }}
        title="Disable Platform user?"
        description="Their current session will stop working on the next request."
        confirmLabel="Disable user"
        danger
        pending={disable.isPending}
        error={disable.error ? errorMessage(disable.error) : undefined}
        onConfirm={() => disable.mutate()}
      />
    </>
  );
}
