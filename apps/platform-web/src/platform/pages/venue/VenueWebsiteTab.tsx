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

type DomainAction = { domain: VenueDomain; kind: "status" | "release"; nextStatus?: DomainStatus };

export function VenueWebsiteTab({ venueId }: { venueId: string }) {
  const queryClient = useQueryClient();
  const product = useQuery({ queryKey: ["product", venueId], queryFn: () => platformApi.product(venueId) });
  const domains = useQuery({ queryKey: ["domains", venueId], queryFn: () => platformApi.domains(venueId) });
  const [mode, setMode] = useState<WebsiteMode | "">("");
  const [modeConfirm, setModeConfirm] = useState(false);
  const [domainOpen, setDomainOpen] = useState(false);
  const [hostname, setHostname] = useState("");
  const [domainAction, setDomainAction] = useState<DomainAction | null>(null);
  const [feedback, setFeedback] = useState<string | null>(null);
  const refreshProduct = async () => { await queryClient.invalidateQueries({ queryKey: ["product", venueId] }); };
  const refreshDomains = async () => { await queryClient.invalidateQueries({ queryKey: ["domains", venueId] }); await queryClient.invalidateQueries({ queryKey: ["audit"] }); };
  const setModeMutation = useMutation({ mutationFn: () => platformApi.setWebsiteMode(venueId, mode as WebsiteMode), onSuccess: async () => { await refreshProduct(); setModeConfirm(false); setMode(""); setFeedback("Website mode updated."); } });
  const register = useMutation({ mutationFn: () => platformApi.registerDomain(venueId, hostname), onSuccess: async () => { await refreshDomains(); setDomainOpen(false); setHostname(""); setFeedback("Domain registered."); } });
  const mutateDomain = useMutation({ mutationFn: async (action: DomainAction) => action.kind === "release" ? platformApi.releaseDomain(venueId, action.domain.id) : platformApi.setDomainStatus(venueId, action.domain.id, action.nextStatus as DomainStatus), onSuccess: async () => { await refreshDomains(); setDomainAction(null); setFeedback("Domain lifecycle updated."); } });

  if (product.isPending || domains.isPending) return <LoadingState label="Loading website configuration" />;
  const failed = product.error ?? domains.error;
  if (failed) return <ErrorState error={errorMessage(failed)} retry={() => { void product.refetch(); void domains.refetch(); }} />;
  if (!product.data || !domains.data) return <LoadingState label="Loading website configuration" />;
  const website = product.data.website;
  const selectedMode = mode || website.configuredMode;

  return <>
    {feedback ? <div className="platform-feedback platform-feedback--success" role="status">{feedback}</div> : null}
    {!website.consistent ? <div className="platform-callout"><WarningCircle size={20} /><div><strong>Website entitlement and configuration disagree</strong><p>Configured mode is {website.configuredMode}, but effective mode is {website.effectiveMode}. Review the two settings before publishing a hostname.</p></div></div> : null}
    <div className="platform-grid platform-grid--2 platform-section-gap">
      <Panel title="Website access" description="Entitlement and mode are independent platform facts."><div className="platform-website-state"><div><span>WEBSITE entitlement</span><StatusBadge value={website.entitled ? "ENABLED" : "DISABLED"} /></div><div><span>Configured mode</span><StatusBadge value={website.configuredMode} /></div><div><span>Effective mode</span><StatusBadge value={website.effectiveMode} /></div><div><span>Consistency</span><StatusBadge value={website.consistent ? "CONSISTENT" : "INCONSISTENT"} /></div></div></Panel>
      <Panel title="Change website mode" description="NONE, SAAS, and CUSTOM describe how an entitled venue is served."><div className="platform-mode-control"><Select aria-label="Website mode" value={selectedMode} onChange={(event) => setMode(event.target.value as WebsiteMode)}><option value="NONE">None</option><option value="SAAS">Vynic SaaS</option><option value="CUSTOM">Custom website</option></Select><Button tone="primary" disabled={!mode || mode === website.configuredMode} onClick={() => setModeConfirm(true)}>Change mode</Button></div></Panel>
    </div>
    <Panel title="Domains" description="Hostnames are normalized and reserved by the backend. DNS and TLS are managed separately." action={<Button tone="primary" onClick={() => setDomainOpen(true)}><Plus size={16} /> Register domain</Button>}>
      {domains.data.length === 0 ? <EmptyState title="No domains registered" body="Register the hostname that should resolve this venue on the public website path." /> : <Table><thead><tr><th>Hostname</th><th>Status</th><th>Registered</th><th aria-label="Actions" /></tr></thead><tbody>{domains.data.map((domain) => <tr key={domain.id}><td><div className="platform-table__primary"><strong><Globe size={15} /> {domain.hostname}</strong><small>{domain.id}</small></div></td><td><StatusBadge value={domain.status} /></td><td>{formatDateTime(domain.createdAt)}</td><td><div className="platform-table__actions"><Button tone="quiet" onClick={() => setDomainAction({ domain, kind: "status", nextStatus: domain.status === "ACTIVE" ? "DISABLED" : "ACTIVE" })}>{domain.status === "ACTIVE" ? "Disable" : "Enable"}</Button><Button tone="danger" onClick={() => setDomainAction({ domain, kind: "release" })}>Release</Button></div></td></tr>)}</tbody></Table>}
    </Panel>
    <ConfirmDialog open={modeConfirm} onOpenChange={setModeConfirm} title={`Change website mode to ${selectedMode}?`} description="This updates only the configured mode. If the WEBSITE entitlement disagrees, the current inconsistency will remain visible until the settings are aligned." confirmLabel="Change mode" pending={setModeMutation.isPending} error={setModeMutation.error ? errorMessage(setModeMutation.error) : undefined} onConfirm={() => setModeMutation.mutate()} />
    <Dialog open={domainOpen} onOpenChange={setDomainOpen} title="Register domain" description="Enter only the hostname. Vynic does not change DNS or TLS here." footer={<><Button onClick={() => setDomainOpen(false)}>Cancel</Button><Button tone="primary" type="submit" form="register-domain" disabled={register.isPending}>Register</Button></>}><form id="register-domain" className="platform-form" onSubmit={(event) => { event.preventDefault(); register.mutate(); }}><Field label="Hostname" hint="Example: restaurant.example.com"><Input value={hostname} onChange={(event) => setHostname(event.target.value)} required maxLength={253} autoFocus /></Field><FormError>{register.error ? errorMessage(register.error) : undefined}</FormError></form></Dialog>
    <ConfirmDialog open={Boolean(domainAction)} onOpenChange={(open) => { if (!open) setDomainAction(null); }} title={domainAction?.kind === "release" ? `Release ${domainAction.domain.hostname}?` : `${domainAction?.nextStatus === "ACTIVE" ? "Enable" : "Disable"} ${domainAction?.domain.hostname}?`} description={domainAction?.kind === "release" ? "This frees the globally unique hostname so another venue can register it. DNS and TLS are not changed." : domainAction?.nextStatus === "ACTIVE" ? "Public host resolution may resume for this hostname if the venue and website configuration also allow it." : "The hostname stays reserved to this venue but will stop resolving publicly."} confirmLabel={domainAction?.kind === "release" ? "Release domain" : "Change status"} danger={domainAction?.kind === "release" || domainAction?.nextStatus === "DISABLED"} pending={mutateDomain.isPending} error={mutateDomain.error ? errorMessage(mutateDomain.error) : undefined} onConfirm={() => { if (domainAction) mutateDomain.mutate(domainAction); }} />
  </>;
}
