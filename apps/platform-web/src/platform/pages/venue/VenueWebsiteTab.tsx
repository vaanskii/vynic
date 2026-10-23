import { WebsitePaymentReviewsPanel } from "./WebsitePaymentReviewsPanel";
import { WebsiteDeliveriesPanel } from "./WebsiteDeliveriesPanel";
import { CustomWebsitePanel } from "./CustomWebsitePanel";
import { WebsiteCapabilitiesPanel } from "./WebsiteCapabilitiesPanel";
import { HostnameReviews } from "./HostnameReviews";
import { useState } from "react";
import { Globe, Plus, WarningCircle } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage, formatDateTime } from "../../format";
import type { DomainStatus, VenueDomain, WebsiteMode } from "../../types";
import { Button } from "../../components/Button";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { Dialog } from "../../components/Dialog";
import { Field, FormError, Input, Select } from "../../components/Form";
import { Panel } from "../../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";
import { Table } from "../../components/Table";

type DomainAction = {
  domain: VenueDomain;
  kind: "status" | "release";
  nextStatus?: DomainStatus;
};

export function VenueWebsiteTab({ venueId }: { venueId: string }) {
  const queryClient = useQueryClient();
  const payments = useQuery({
    queryKey: ["payments", venueId],
    queryFn: () => platformApi.paymentStatus(venueId),
  });
  const product = useQuery({
    queryKey: ["product", venueId],
    queryFn: () => platformApi.product(venueId),
  });
  const domains = useQuery({
    queryKey: ["domains", venueId],
    queryFn: () => platformApi.domains(venueId),
  });
  const [mode, setMode] = useState<WebsiteMode | "">("");
  const [modeConfirm, setModeConfirm] = useState(false);
  const [domainOpen, setDomainOpen] = useState(false);
  const [hostname, setHostname] = useState("");
  const [editingDomain, setEditingDomain] = useState<VenueDomain | null>(null);
  const [editHostname, setEditHostname] = useState("");
  const [editReason, setEditReason] = useState("");
  const [domainAction, setDomainAction] = useState<DomainAction | null>(null);
  const [feedback, setFeedback] = useState<string | null>(null);
  const refreshProduct = async () => {
    await queryClient.invalidateQueries({ queryKey: ["product", venueId] });
    await queryClient.invalidateQueries({
      queryKey: ["website-capabilities", venueId],
    });
    await queryClient.invalidateQueries({
      queryKey: ["custom-website", venueId],
    });
  };
  const refreshDomains = async () => {
    await queryClient.invalidateQueries({ queryKey: ["domains", venueId] });
    await queryClient.invalidateQueries({
      queryKey: ["custom-website", venueId],
    });
    await queryClient.invalidateQueries({ queryKey: ["audit"] });
  };
  const setModeMutation = useMutation({
    mutationFn: () => platformApi.setWebsiteMode(venueId, mode as WebsiteMode),
    onSuccess: async () => {
      await refreshProduct();
      setModeConfirm(false);
      setMode("");
      setFeedback("Website mode updated.");
    },
  });
  const register = useMutation({
    mutationFn: () => platformApi.registerDomain(venueId, hostname),
    onSuccess: async () => {
      await refreshDomains();
      setDomainOpen(false);
      setHostname("");
      setFeedback(
        "Domain saved as pending. Connect DNS and the correct frontend, check HTTPS, then activate the binding.",
      );
    },
  });
  const mutateDomain = useMutation({
    mutationFn: async (action: DomainAction) =>
      action.kind === "release"
        ? platformApi.releaseDomain(venueId, action.domain.id)
        : platformApi.setDomainStatus(
            venueId,
            action.domain.id,
            action.nextStatus as DomainStatus,
          ),
    onSuccess: async () => {
      await refreshDomains();
      setDomainAction(null);
      setFeedback("Domain lifecycle updated.");
    },
  });
  const rename = useMutation({
    mutationFn: () =>
      platformApi.renameDomain(
        venueId,
        editingDomain!.id,
        editHostname,
        editingDomain!.hostname,
        editReason,
      ),
    onSuccess: async () => {
      await Promise.all([
        refreshDomains(),
        refreshProduct(),
        queryClient.invalidateQueries({
          queryKey: ["hostname-requests", venueId],
        }),
      ]);
      setEditingDomain(null);
      setFeedback(
        "Hostname changed. Check DNS, TLS and the website route for the new address.",
      );
    },
  });

  if (product.isPending || domains.isPending)
    return <LoadingState label="Loading website configuration" />;
  const failed = product.error ?? domains.error;
  if (failed)
    return (
      <ErrorState
        error={errorMessage(failed)}
        retry={() => {
          void product.refetch();
          void domains.refetch();
        }}
      />
    );
  if (!product.data || !domains.data)
    return <LoadingState label="Loading website configuration" />;
  const website = product.data.website;
  const selectedMode = mode || website.configuredMode;
  const assignedSlug = website.provisioning?.assignedSlug;
  // Address role is separate from the renderer: CUSTOM can use a Vynic subdomain.
  const saasHostname =
    website.configuredMode === "SAAS" && assignedSlug
      ? website.hostname !== undefined
        ? website.hostname
        : (domains.data.find((d) => d.hostname.startsWith(`${assignedSlug}.`))
            ?.hostname ?? null)
      : null;
  const isSaasDomain = (hostname: string) => saasHostname === hostname;
  const customDomains = domains.data.filter((d) => !isSaasDomain(d.hostname));

  return (
    <>
      <HostnameReviews
        venueId={venueId}
        saas={website.configuredMode === "SAAS"}
        currentHostname={saasHostname}
      />
      <Panel
        title="Online payments · Bank of Georgia"
        description="Manage ONLINE_PAYMENTS in Product access. Restaurant owners configure credentials in their dashboard."
      >
        {payments.isPending ? (
          <p>Loading payment configuration…</p>
        ) : payments.isError ? (
          <ErrorState
            error="Could not load payment configuration"
            retry={() => {
              void payments.refetch();
            }}
          />
        ) : (
          <p>
            {payments.data.configured ? "Configured" : "Not configured"} ·
            ONLINE_PAYMENTS {payments.data.entitled ? "enabled" : "disabled"}
          </p>
        )}
      </Panel>
      {feedback ? (
        <div
          className="platform-feedback platform-feedback--success"
          role="status"
        >
          {feedback}
        </div>
      ) : null}
      {!website.consistent ? (
        <div className="platform-callout">
          <WarningCircle size={20} />
          <div>
            <strong>Website entitlement and configuration disagree</strong>
            <p>
              Configured mode is {website.configuredMode}, but effective mode is{" "}
              {website.effectiveMode}. Review the two settings before publishing
              a hostname.
            </p>
          </div>
        </div>
      ) : null}
      <div className="platform-grid platform-grid--2 platform-section-gap">
        <Panel
          title="Website access"
          description="Entitlement and mode are independent platform facts."
        >
          <div className="platform-website-state">
            <div>
              <span>WEBSITE entitlement</span>
              <StatusBadge value={website.entitled ? "ENABLED" : "DISABLED"} />
            </div>
            <div>
              <span>Configured mode</span>
              <StatusBadge value={website.configuredMode} />
            </div>
            <div>
              <span>Effective mode</span>
              <StatusBadge value={website.effectiveMode} />
            </div>
            <div>
              <span>Provisioning</span>
              <span>
                {website.configuredMode === "NONE"
                  ? "Setup pending"
                  : (website.provisioning?.status ?? "DRAFT")}
              </span>
            </div>
          </div>
        </Panel>
        <Panel
          title="Change website mode"
          description="NONE, SAAS, and CUSTOM describe how an entitled venue is served."
        >
          <div className="platform-mode-control">
            <Select
              aria-label="Website mode"
              value={selectedMode}
              onChange={(event) => setMode(event.target.value as WebsiteMode)}
            >
              <option value="NONE">None</option>
              <option value="SAAS">Vynic SaaS</option>
              <option value="CUSTOM">Custom website</option>
            </Select>
            <Button
              tone="primary"
              disabled={!mode || mode === website.configuredMode}
              onClick={() => setModeConfirm(true)}
            >
              Change mode
            </Button>
          </div>
        </Panel>
      </div>
      <WebsitePaymentReviewsPanel
        key={`payments-${venueId}`}
        venueId={venueId}
      />
      <WebsiteDeliveriesPanel key={venueId} venueId={venueId} />
      {website.configuredMode === "CUSTOM" ? (
        <CustomWebsitePanel venueId={venueId} />
      ) : null}
      {website.configuredMode !== "NONE" ? (
        <div className="platform-section-gap">
          <WebsiteCapabilitiesPanel venueId={venueId} />
        </div>
      ) : null}
      <Panel title="Website publication">
        <p>
          Current SaaS address:{" "}
          {website.configuredMode === "SAAS"
            ? (saasHostname ??
              (assignedSlug ? `${assignedSlug} (not bound)` : "Not assigned"))
            : "Not applicable"}
        </p>
        <p>
          Additional hostnames:{" "}
          {customDomains.length
            ? customDomains.map((d) => d.hostname).join(", ")
            : "None"}
        </p>
        <p>
          Publication: {website.provisioning?.status ?? "DRAFT"} ·{" "}
          {formatDateTime(website.provisioning?.publishedAt)}
        </p>
        <p>
          Menu authority: {product.data.menuManagement?.authority ?? "—"} ·
          Cloud editing{" "}
          {product.data.menuManagement?.enabled ? "enabled" : "disabled"}
        </p>
      </Panel>
      <Panel
        title="Domains"
        description="Each hostname belongs to one restaurant. Saving here updates the database only: it does not provision DNS, Vercel or SSL. Pending bindings do not serve restaurant data; active bindings still require website access and publication."
        action={
          <Button tone="primary" onClick={() => setDomainOpen(true)}>
            <Plus size={16} /> Register domain
          </Button>
        }
      >
        <p>
          Renderer: <strong>{website.configuredMode}</strong>.{" "}
          {website.configuredMode === "SAAS"
            ? "Connect all SaaS restaurant addresses to the shared vynic-restaurant-web project."
            : website.configuredMode === "CUSTOM"
              ? "Connect this address to the restaurant’s own CUSTOM project (Vankisi: vynic-vankisi-custom-web)."
              : "Choose a website mode before connecting a frontend."}{" "}
          Verify the exact host in Vercel, its DNS record and HTTPS before
          activating. Binding status is not a live DNS or SSL check.
        </p>
        {domains.data.length === 0 ? (
          <EmptyState
            title="No domains registered"
            body="Register the hostname that should resolve this venue on the public website path."
          />
        ) : (
          <Table>
            <thead>
              <tr>
                <th>Hostname</th>
                <th>Database binding</th>
                <th>Registered</th>
                <th aria-label="Actions" />
              </tr>
            </thead>
            <tbody>
              {domains.data.map((domain) => (
                <tr key={domain.id}>
                  <td>
                    <div className="platform-table__primary">
                      <strong>
                        <Globe size={15} /> {domain.hostname}
                      </strong>
                      <small>
                        {isSaasDomain(domain.hostname)
                          ? "Assigned SaaS address"
                          : "Additional hostname"}{" "}
                        · {website.configuredMode} · {domain.id}
                      </small>
                    </div>
                  </td>
                  <td>
                    <StatusBadge value={domain.status}>
                      {domain.status === "PENDING"
                        ? "Pending connection"
                        : domain.status === "ACTIVE"
                          ? "Active binding"
                          : "Disabled binding"}
                    </StatusBadge>
                  </td>
                  <td>{formatDateTime(domain.createdAt)}</td>
                  <td>
                    <div className="platform-table__actions">
                      <Button
                        tone="quiet"
                        onClick={() => {
                          rename.reset();
                          setEditingDomain(domain);
                          setEditHostname(domain.hostname);
                          setEditReason("");
                        }}
                      >
                        Change hostname
                      </Button>
                      <Button
                        tone="quiet"
                        onClick={() =>
                          setDomainAction({
                            domain,
                            kind: "status",
                            nextStatus:
                              domain.status === "ACTIVE"
                                ? "DISABLED"
                                : "ACTIVE",
                          })
                        }
                      >
                        {domain.status === "ACTIVE"
                          ? "Disable"
                          : "Activate binding"}
                      </Button>
                      <Button
                        tone="danger"
                        onClick={() =>
                          setDomainAction({ domain, kind: "release" })
                        }
                      >
                        Release
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Panel>
      <ConfirmDialog
        open={modeConfirm}
        onOpenChange={setModeConfirm}
        title={`Change website mode to ${selectedMode}?`}
        description="This updates only the configured mode. If the WEBSITE entitlement disagrees, the current inconsistency will remain visible until the settings are aligned."
        confirmLabel="Change mode"
        pending={setModeMutation.isPending}
        error={
          setModeMutation.error
            ? errorMessage(setModeMutation.error)
            : undefined
        }
        onConfirm={() => setModeMutation.mutate()}
      />
      <Dialog
        open={domainOpen}
        onOpenChange={setDomainOpen}
        title="Register domain"
        description="Enter only the hostname. It will be saved as pending. Connect the correct Vercel project, apply its exact DNS record and verify HTTPS before activating the binding."
        footer={
          <>
            <Button onClick={() => setDomainOpen(false)}>Cancel</Button>
            <Button
              tone="primary"
              type="submit"
              form="register-domain"
              disabled={register.isPending}
            >
              Register
            </Button>
          </>
        }
      >
        <form
          id="register-domain"
          className="platform-form"
          onSubmit={(event) => {
            event.preventDefault();
            register.mutate();
          }}
        >
          <Field label="Hostname" hint="Example: restaurant.example.com">
            <Input
              value={hostname}
              onChange={(event) => setHostname(event.target.value)}
              required
              maxLength={253}
              autoFocus
            />
          </Field>
          <FormError>
            {register.error ? errorMessage(register.error) : undefined}
          </FormError>
        </form>
      </Dialog>
      <Dialog
        open={!!editingDomain}
        onOpenChange={(open) => {
          if (!open) setEditingDomain(null);
        }}
        title="Change hostname"
        description={`Replace ${editingDomain?.hostname ?? "the current hostname"}. The old hostname will stop resolving to this restaurant. DNS, TLS and website routing must match the new address.`}
        footer={
          <>
            <Button onClick={() => setEditingDomain(null)}>Cancel</Button>
            <Button
              tone="primary"
              type="submit"
              form="rename-domain"
              disabled={
                rename.isPending ||
                !editHostname.trim() ||
                editHostname === editingDomain?.hostname ||
                !editReason.trim()
              }
            >
              Save hostname
            </Button>
          </>
        }
      >
        <form
          id="rename-domain"
          className="platform-form"
          onSubmit={(event) => {
            event.preventDefault();
            rename.mutate();
          }}
        >
          <Field
            label="New hostname"
            hint="Example: restaurant.vynic.ge or restaurant.example.com"
          >
            <Input
              value={editHostname}
              onChange={(event) => setEditHostname(event.target.value)}
              required
              maxLength={253}
              autoFocus
            />
          </Field>
          <Field label="Change reason">
            <Input
              value={editReason}
              onChange={(event) => setEditReason(event.target.value)}
              required
              maxLength={1000}
            />
          </Field>
          <FormError>
            {rename.error ? errorMessage(rename.error) : undefined}
          </FormError>
        </form>
      </Dialog>
      <ConfirmDialog
        open={Boolean(domainAction)}
        onOpenChange={(open) => {
          if (!open) setDomainAction(null);
        }}
        title={
          domainAction?.kind === "release"
            ? `Release ${domainAction.domain.hostname}?`
            : `${domainAction?.nextStatus === "ACTIVE" ? "Activate binding for" : "Disable"} ${domainAction?.domain.hostname}?`
        }
        description={
          domainAction?.kind === "release"
            ? "This frees the globally unique hostname so another venue can register it. DNS and TLS are not changed."
            : domainAction?.nextStatus === "ACTIVE"
              ? "Confirm that this exact hostname is connected to the correct frontend, DNS resolves and HTTPS is valid. This activates only the database binding; it does not verify infrastructure. Website access and publication must also allow serving."
              : "The hostname stays reserved to this venue but will stop resolving publicly."
        }
        confirmLabel={
          domainAction?.kind === "release" ? "Release domain" : "Change status"
        }
        danger={
          domainAction?.kind === "release" ||
          domainAction?.nextStatus === "DISABLED"
        }
        pending={mutateDomain.isPending}
        error={
          mutateDomain.error ? errorMessage(mutateDomain.error) : undefined
        }
        onConfirm={() => {
          if (domainAction) mutateDomain.mutate(domainAction);
        }}
      />
    </>
  );
}
