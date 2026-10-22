import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage } from "../../format";
import type { WebsiteCapability } from "../../types";
import { Button } from "../../components/Button";
import { FormError } from "../../components/Form";
import { Panel } from "../../components/Page";
import { ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";
import { Table } from "../../components/Table";

function frontendLabel(capability: WebsiteCapability) {
  if (!capability.built) return "—";
  if (capability.usedByFrontend === null) return "Custom build decides";
  return capability.usedByFrontend ? "Shown" : "Not shown";
}

/**
 * The Venue's shared website capabilities, identical for SAAS and CUSTOM.
 *
 * Commercial availability comes from Product, configuration from the owner
 * (menu, hours, photos, payments) or the operator (tables); only the per-Venue
 * on/off policy is switched here. An impossible switch is never offered:
 * nothing unbuilt, and nothing the package does not include.
 */
export function WebsiteCapabilitiesPanel({ venueId }: { venueId: string }) {
  const queryClient = useQueryClient();
  const capabilities = useQuery({
    queryKey: ["website-capabilities", venueId],
    queryFn: () => platformApi.websiteCapabilities(venueId),
  });
  const toggle = useMutation({
    mutationFn: (value: { key: string; enabled: boolean }) =>
      platformApi.setWebsiteCapability(venueId, value.key, value.enabled),
    onSuccess: async (next) => {
      queryClient.setQueryData(["website-capabilities", venueId], next);
      await queryClient.invalidateQueries({ queryKey: ["audit"] });
      await queryClient.invalidateQueries({
        queryKey: ["custom-website", venueId],
      });
    },
  });

  return (
    <Panel
      title="Website capabilities"
      description="Shared by every website renderer: SAAS and CUSTOM read the same backend. Entitlement is set in Product; the switch here is this Venue's policy."
    >
      {capabilities.isPending ? (
        <LoadingState label="Loading website capabilities" />
      ) : capabilities.isError ? (
        <ErrorState
          error={errorMessage(capabilities.error)}
          retry={() => void capabilities.refetch()}
        />
      ) : (
        <>
          <Table>
            <thead>
              <tr>
                <th>Capability</th>
                <th>Commercially available</th>
                <th>Enabled for this Venue</th>
                <th>Backend ready</th>
                <th>Current frontend</th>
              </tr>
            </thead>
            <tbody>
              {capabilities.data.map((c) => (
                <tr key={c.key} data-capability={c.key}>
                  <td>
                    <strong>{c.label}</strong>
                  </td>
                  <td>
                    {c.built ? (
                      <StatusBadge
                        value={c.commercial ? "ENABLED" : "DISABLED"}
                      >
                        {c.commercial ? "Included" : "Not included"}
                      </StatusBadge>
                    ) : (
                      <StatusBadge value="NONE">Not built</StatusBadge>
                    )}
                  </td>
                  <td>
                    {c.built ? (
                      <div className="platform-inline-actions platform-inline-actions--tight">
                        <StatusBadge value={c.enabled ? "ENABLED" : "DISABLED"}>
                          {c.enabled ? "On" : "Off"}
                        </StatusBadge>
                        <Button
                          aria-label={`${c.enabled ? "Turn off" : "Turn on"} ${c.label}`}
                          tone={c.enabled ? "quiet" : "secondary"}
                          disabled={
                            toggle.isPending || (!c.enabled && !c.canEnable)
                          }
                          title={
                            !c.enabled && !c.canEnable
                              ? "Not included in this Venue's package"
                              : undefined
                          }
                          onClick={() =>
                            toggle.mutate({ key: c.key, enabled: !c.enabled })
                          }
                        >
                          {c.enabled ? "Turn off" : "Turn on"}
                        </Button>
                      </div>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    {c.built ? (
                      <>
                        <StatusBadge value={c.ready ? "ENABLED" : "DISABLED"}>
                          {c.ready ? "Ready" : "Not ready"}
                        </StatusBadge>
                        {c.readyDetail ? <small> {c.readyDetail}</small> : null}
                      </>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>{frontendLabel(c)}</td>
                </tr>
              ))}
            </tbody>
          </Table>
          <FormError>
            {toggle.error ? errorMessage(toggle.error) : undefined}
          </FormError>
        </>
      )}
    </Panel>
  );
}
