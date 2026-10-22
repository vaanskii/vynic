import 'package:vynic/core/services/printing/printer_agent_profile.dart';
import 'package:vynic/core/services/printing/printer_agent_runtime_profile.dart';

const agentDevice = '00000000-0000-4000-8000-000000000101';
const agentVenue = '00000000-0000-4000-8000-000000000102';
const agentInstallation = '00000000-0000-4000-8000-000000000103';
const agentDeviceInstallation = '00000000-0000-4000-8000-000000000108';
const agentHost = '00000000-0000-4000-8000-000000000104';
const agentClient = '00000000-0000-4000-8000-000000000105';
const agentOther = '00000000-0000-4000-8000-000000000106';
const agentPrinter = '00000000-0000-4000-8000-000000000107';

PrinterAgentPins agentPins({
  PrinterAgentScope scope = PrinterAgentScope.local,
  String device = agentDevice,
  String venue = agentVenue,
  String installation = agentInstallation,
  int configRevision = 1,
}) => PrinterAgentPins(
  scope: scope,
  ownershipPolicy: scope == PrinterAgentScope.local
      ? 'localHost'
      : 'clusterLogicalOnly',
  clusterId: scope == PrinterAgentScope.local ? '' : agentOther,
  membershipSha256: scope == PrinterAgentScope.local ? '' : 'd' * 64,
  role: 'posAgent',
  venueId: venue,
  installationId: installation,
  deviceId: device,
  hostId: agentHost,
  gatewayHostId: scope == PrinterAgentScope.local ? agentHost : '',
  authorityEpoch: 1,
  protocolVersion: 1,
  helperProtocolVersion: 1,
  databaseSchemaVersion: 6,
  minimumReaderVersion: 2,
  routeRevision: 1,
  configRevision: configRevision,
  registryRevision: 1,
  bindingRevision: 1,
  capabilityRevision: 1,
  capabilityProfileSha256: 'a' * 64,
  hostBinarySha256: 'b' * 64,
  helperBinarySha256: 'c' * 64,
);

const agentBinding = PrinterAgentRuntimeBinding(
  deviceId: agentDevice,
  venueId: agentVenue,
  deviceInstallationId: agentDeviceInstallation,
  loaded: true,
  enrolled: true,
);

PrinterAgentHealth agentHealth({
  PrinterAgentPins? pins,
  PrinterAgentLifecycle state = PrinterAgentLifecycle.running,
  bool ready = true,
  bool queueHeld = false,
  String holdReason = 'primary_uncertain',
}) {
  final bound = pins ?? agentPins();
  return PrinterAgentHealth(
    pins: bound,
    clientId: agentClient,
    state: state,
    softwareReady: ready,
    holdReasons: [
      PrinterAgentHoldReason.provisioningUnqualified,
      PrinterAgentHoldReason.physicalActivationPending,
      if (bound.scope == PrinterAgentScope.venueShared)
        PrinterAgentHoldReason.sharedFenceUnqualified,
      if (queueHeld) PrinterAgentHoldReason.retainedQueueHold,
    ],
    printerHolds: queueHeld
        ? [
            PrinterAgentPrinterHold(
              physicalPrinterId: agentPrinter,
              reason: holdReason,
            ),
          ]
        : [],
  );
}

/// Widget state seam only. Actual mTLS client qualification is a separate
/// fixture; this deliberately exposes health and never a print operation.
class FakeAgentHealthSource implements PrinterAgentRuntimeHealthSource {
  FakeAgentHealthSource({
    this.configured = true,
    this.binding = agentBinding,
    required this.result,
  });
  bool configured;
  PrinterAgentRuntimeBinding binding;
  final Future<PrinterAgentHealth> Function() result;
  int healthCalls = 0;
  @override
  bool get isConfigured => configured;
  @override
  PrinterAgentRuntimeBinding get currentBinding => binding;
  @override
  Future<PrinterAgentHealth> health() {
    healthCalls++;
    return result();
  }
}
