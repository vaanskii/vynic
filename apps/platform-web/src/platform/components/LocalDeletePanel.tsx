import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate } from "react-router-dom";
import { localToolsApi } from "../api";
import { useAuth } from "../auth";
import { errorMessage } from "../format";
import { Button } from "./Button";
import { Dialog } from "./Dialog";
import { Field, FormError, Input } from "./Form";
import { Panel } from "./Page";
import { ErrorState } from "./State";

export function LocalDeletePanel({
  kind,
  id,
  name,
}: {
  kind: "venue" | "organization";
  id: string;
  name: string;
}) {
  const { actor } = useAuth();
  const capability = useQuery({
    queryKey: ["local-database-tools"],
    queryFn: localToolsApi.capability,
    retry: false,
  });
  const [open, setOpen] = useState(false);
  const [confirmation, setConfirmation] = useState("");
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const directory = kind === "venue" ? "/venues" : "/organizations";
  const deletion = useMutation({
    mutationFn: () => localToolsApi.remove(kind, id, confirmation),
    onSuccess: async (result) => {
      if (result.mediaCleanup.failures.length) return;
      await queryClient.invalidateQueries();
      navigate(directory, { replace: true });
    },
  });
  if (capability.error)
    return (
      <ErrorState
        error={errorMessage(capability.error)}
        retry={() => void capability.refetch()}
      />
    );
  if (!capability.data?.enabled || actor?.role === "SUPPORT_READONLY")
    return null;
  const deletedWithWarnings =
    deletion.isSuccess && deletion.data.mediaCleanup.failures.length > 0;
  return (
    <Panel
      title="Developer tools · Local Docker only"
      description="Permanently delete local test data. Platform accounts, plans and configuration are preserved."
    >
      <p>
        {kind === "venue"
          ? "Deletes this venue and its business data. Its organization, other venues and customer accounts remain."
          : "Deletes this organization and all its venues. Customer accounts linked to another organization remain."}{" "}
        Shared website identities remain.
      </p>
      <Button
        tone="danger"
        onClick={() => {
          setConfirmation("");
          deletion.reset();
          setOpen(true);
        }}
      >
        Delete test {kind}
      </Button>
      <Dialog
        open={open}
        onOpenChange={(next) => {
          if (!deletion.isPending && !deletedWithWarnings) setOpen(next);
        }}
        title={`Delete test ${kind}`}
        description={`Permanently delete ${name} and its owned business data.`}
        footer={
          deletedWithWarnings ? (
            <Link className="platform-text-link" to={directory}>
              Return to {kind === "venue" ? "venues" : "organizations"}
            </Link>
          ) : (
            <>
              <Button
                disabled={deletion.isPending}
                onClick={() => setOpen(false)}
              >
                Cancel
              </Button>
              <Button
                tone="danger"
                disabled={
                  confirmation !== `DELETE ${name}` || deletion.isPending
                }
                loading={deletion.isPending}
                onClick={() => deletion.mutate()}
              >
                Delete test {kind}
              </Button>
            </>
          )
        }
      >
        {deletedWithWarnings ? (
          <div role="alert">
            <p>
              The database deletion succeeded, but media cleanup needs
              attention. Run{" "}
              <code>
                ./scripts/docker.sh cleanup-customer-media --confirm-local
              </code>{" "}
              in the local workspace.
            </p>
            <p style={{ overflowWrap: "anywhere" }}>
              {deletion.data.mediaCleanup.failures.join("; ")}
            </p>
          </div>
        ) : (
          <>
            <Field label={`Type DELETE ${name} to confirm`}>
              <Input
                value={confirmation}
                onChange={(event) => setConfirmation(event.target.value)}
                autoComplete="off"
                name="delete-confirmation"
                spellCheck={false}
                disabled={deletion.isPending}
              />
            </Field>
            <FormError>
              {deletion.error ? errorMessage(deletion.error) : undefined}
            </FormError>
          </>
        )}
      </Dialog>
    </Panel>
  );
}
