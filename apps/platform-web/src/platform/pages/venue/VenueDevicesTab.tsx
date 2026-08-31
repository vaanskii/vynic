import { useEffect, useState } from "react";
import { Copy, DownloadSimple, Eye, EyeSlash, Plus, Pulse, WarningCircle } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { errorMessage, formatRelativeTime } from "../../format";
import type { Device, DeviceStatus, IssuedCredential } from "../../types";
import { Button } from "../../components/Button";
import { ConfirmDialog } from "../../components/ConfirmDialog";
import { Dialog } from "../../components/Dialog";
import { Field, FormError, Input, Select } from "../../components/Form";
import { Panel } from "../../components/Page";
import { EmptyState, ErrorState, LoadingState } from "../../components/State";
import { StatusBadge } from "../../components/StatusBadge";
import { Table } from "../../components/Table";
import { downloadProvisioningFile } from "../../provisioning";

type DeviceAction = { device: Device; kind: "status" | "rotate"; nextStatus?: DeviceStatus };

export function VenueDevicesTab({ venueId, venueName }: { venueId: string; venueName: string }) {
  const queryClient = useQueryClient();
  const devices = useQuery({ queryKey: ["devices", venueId], queryFn: () => platformApi.devices(venueId) });
  const [createOpen, setCreateOpen] = useState(false);
  const [form, setForm] = useState({ displayName: "", platform: "WINDOWS", installationId: "" });
  const [issued, setIssued] = useState<IssuedCredential | null>(null);
  const [revealed, setRevealed] = useState(false);
  const [copied, setCopied] = useState(false);
  const [deviceAction, setDeviceAction] = useState<DeviceAction | null>(null);
  const [testDeviceId, setTestDeviceId] = useState("");
  const [queued, setQueued] = useState<{ commandId: string; status: string } | null>(null);
  const refresh = async () => { await queryClient.invalidateQueries({ queryKey: ["devices", venueId] }); await queryClient.invalidateQueries({ queryKey: ["audit"] }); };
  const create = useMutation({ mutationFn: async () => {
    const result = await platformApi.createDevice(venueId, { displayName: form.displayName, platform: form.platform, installationId: form.installationId || undefined });
    setIssued(result);
    return result.device;
  }, onSuccess: async () => { await refresh(); setCreateOpen(false); setForm({ displayName: "", platform: "WINDOWS", installationId: "" }); } });
  const mutateDevice = useMutation({ mutationFn: async (action: DeviceAction) => {
    if (action.kind === "rotate") {
      const result = await platformApi.rotateCredential(venueId, action.device.id);
      setIssued(result);
      return result.device;
    }
    return platformApi.setDeviceStatus(venueId, action.device.id, action.nextStatus as DeviceStatus);
  }, onSuccess: async () => { await refresh(); setDeviceAction(null); } });
  const testCommand = useMutation({ mutationFn: () => platformApi.queueTestCommand(venueId, testDeviceId || undefined), onSuccess: (result) => setQueued({ commandId: result.commandId, status: result.status }) });
  const resetCreate = create.reset;
  const resetDeviceMutation = mutateDevice.reset;

  useEffect(() => () => {
    resetCreate();
    resetDeviceMutation();
  }, [resetCreate, resetDeviceMutation]);

  if (devices.isPending) return <LoadingState label="Loading devices" />;
  if (devices.error) return <ErrorState error={errorMessage(devices.error)} retry={() => void devices.refetch()} />;

  const closeSecret = () => {
    setIssued(null);
    setRevealed(false);
    setCopied(false);
    create.reset();
    mutateDevice.reset();
  };
  return <>
    <Panel title="POS devices" description="Last seen is a timestamp from the backend. Vynic does not infer a fake online/offline state." action={<Button tone="primary" onClick={() => setCreateOpen(true)}><Plus size={16} /> Add POS device</Button>}>
      {devices.data.length === 0 ? <EmptyState title="No POS devices" body="Create a device to issue its one-time Edge credential." /> : <Table><thead><tr><th>Device</th><th>Platform</th><th>Status</th><th>Connection activity</th><th aria-label="Actions" /></tr></thead><tbody>{devices.data.map((device) => <tr key={device.id}><td><div className="platform-table__primary"><strong>{device.displayName}</strong><small>{device.installationId}</small></div></td><td>{device.platform}</td><td><StatusBadge value={device.status} /></td><td>{formatRelativeTime(device.lastSeenAt)}</td><td><div className="platform-table__actions"><Button tone="quiet" onClick={() => setDeviceAction({ device, kind: "rotate" })}>Rotate credential</Button>{device.status === "ACTIVE" ? <><Button tone="quiet" onClick={() => setDeviceAction({ device, kind: "status", nextStatus: "DISABLED" })}>Disable</Button><Button tone="danger" onClick={() => setDeviceAction({ device, kind: "status", nextStatus: "REVOKED" })}>Revoke</Button></> : <Button tone="secondary" onClick={() => setDeviceAction({ device, kind: "status", nextStatus: "ACTIVE" })}>Activate</Button>}</div></td></tr>)}</tbody></Table>}
    </Panel>
    <Panel title="Send connection test" description="Queues a safe asynchronous NOOP for the venue or one device. A queued command does not prove the POS executed it.">
      <div className="platform-test-command"><Field label="Target"><Select value={testDeviceId} onChange={(event) => { setTestDeviceId(event.target.value); setQueued(null); }}><option value="">All active devices in {venueName}</option>{devices.data.map((device) => <option key={device.id} value={device.id}>{device.displayName}</option>)}</Select></Field><Button tone="primary" onClick={() => testCommand.mutate()} disabled={testCommand.isPending}><Pulse size={16} /> {testCommand.isPending ? "Queueing…" : "Send connection test"}</Button></div>
      {testCommand.error ? <FormError>{errorMessage(testCommand.error)}</FormError> : null}
      {queued ? <div className="platform-queued-result"><StatusBadge value="QUEUED" /><div><strong>Command queued</strong><p>The backend accepted command <span className="platform-mono">{queued.commandId}</span> with status {queued.status}. Execution is not proven by this response.</p></div></div> : null}
    </Panel>
    <Dialog open={createOpen} onOpenChange={setCreateOpen} title="Add POS device" description="The backend will issue a credential once. Be ready to copy or download it before closing the next dialog." footer={<><Button onClick={() => setCreateOpen(false)}>Cancel</Button><Button tone="primary" type="submit" form="create-device" disabled={create.isPending}>Create device</Button></>}><form id="create-device" className="platform-form" onSubmit={(event) => { event.preventDefault(); create.mutate(); }}><Field label="Display name"><Input value={form.displayName} onChange={(event) => setForm({ ...form, displayName: event.target.value })} required maxLength={200} autoFocus /></Field><Field label="Platform"><Input value={form.platform} onChange={(event) => setForm({ ...form, platform: event.target.value.toUpperCase() })} required maxLength={32} /></Field><Field label="Installation ID" hint="Optional UUID. Leave empty to let the backend generate one."><Input value={form.installationId} onChange={(event) => setForm({ ...form, installationId: event.target.value })} /></Field><FormError>{create.error ? errorMessage(create.error) : undefined}</FormError></form></Dialog>
    <Dialog open={Boolean(issued)} onOpenChange={(open) => { if (!open) closeSecret(); }} title="Device credential issued" description="This secret is shown only once. If it is lost, rotate the credential." footer={<Button tone="primary" onClick={closeSecret}>I saved the credential</Button>}>
      {issued ? <div className="platform-secret"><div className="platform-callout"><WarningCircle size={19} /><div><strong>One-time secret</strong><p>Closing this dialog removes the credential from frontend state. Normal Device reads cannot recover it.</p></div></div><div className="platform-secret__value"><code>{revealed ? issued.credential : "••••••••••••••••••••••••••••••••"}</code><Button tone="quiet" aria-label={revealed ? "Hide credential" : "Reveal credential"} onClick={() => setRevealed((value) => !value)}>{revealed ? <EyeSlash size={17} /> : <Eye size={17} />}{revealed ? "Hide" : "Reveal"}</Button></div><div className="platform-secret__actions"><Button onClick={async () => { await navigator.clipboard.writeText(issued.credential); setCopied(true); }}><Copy size={16} /> {copied ? "Copied" : "Copy credential"}</Button><Button onClick={() => downloadProvisioningFile(issued.credential)}><DownloadSimple size={16} /> Download provisioning file</Button></div><dl className="platform-detail-grid"><div className="platform-detail"><dt>Device ID</dt><dd className="platform-mono">{issued.device.id}</dd></div><div className="platform-detail"><dt>Installation ID</dt><dd className="platform-mono">{issued.device.installationId}</dd></div></dl></div> : null}
    </Dialog>
    <ConfirmDialog open={Boolean(deviceAction)} onOpenChange={(open) => { if (!open) setDeviceAction(null); }} title={deviceAction?.kind === "rotate" ? `Rotate credential for ${deviceAction.device.displayName}?` : `${deviceAction?.nextStatus === "REVOKED" ? "Revoke" : deviceAction?.nextStatus === "DISABLED" ? "Disable" : "Activate"} ${deviceAction?.device.displayName}?`} description={deviceAction?.kind === "rotate" ? "The current POS credential will immediately stop working. The replacement will be shown only once." : deviceAction?.nextStatus === "REVOKED" ? "The credential will stop authenticating immediately. Revoked records remain in the audit trail and can only be reactivated deliberately." : deviceAction?.nextStatus === "DISABLED" ? "The credential will stop authenticating until the device is activated again. No credential is rotated." : "The existing credential may authenticate again immediately. No new credential is issued."} confirmLabel={deviceAction?.kind === "rotate" ? "Rotate and issue new credential" : "Change device status"} danger={deviceAction?.kind === "rotate" || deviceAction?.nextStatus === "REVOKED"} pending={mutateDevice.isPending} onConfirm={() => { if (deviceAction) mutateDevice.mutate(deviceAction); }} />
  </>;
}
