import 'dart:typed_data';

const printerAgentServerName = 'vynic-printer-agent.local';
const printerAgentCapability = 'printer.agent.health.v1';
const printerAgentMaxInteger = 9223372036854775807;

enum PrinterAgentScope { local, venueShared }

enum PrinterAgentLifecycle {
  newHost,
  starting,
  running,
  draining,
  stopped,
  held,
}

enum PrinterAgentHoldReason {
  provisioningUnqualified,
  physicalActivationPending,
  sharedFenceUnqualified,
  hostUnavailable,
  retainedQueueHold,
}

enum PrinterAgentFailure {
  invalidProfile,
  authentication,
  unavailable,
  profileMismatch,
  provisioningHeld,
  protocolMismatch,
}

class PrinterAgentException implements Exception {
  const PrinterAgentException(this.reason);
  final PrinterAgentFailure reason;
  @override
  String toString() => 'PrinterAgentException(${reason.name})';
}

bool printerAgentUuid(String value) =>
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value) &&
    value != '00000000-0000-0000-0000-000000000000';
bool printerAgentDigest(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
bool printerAgentRevision(int value) =>
    value > 0 && value <= printerAgentMaxInteger;

/// Exact configured evidence. It does not grant Device/Venue, job or physical
/// authority. Host identity is explicitly provisioned, never derived from a
/// printer address, an installation UUID or a discovery response.
class PrinterAgentPins {
  PrinterAgentPins({
    required this.scope,
    required this.ownershipPolicy,
    required this.clusterId,
    required this.membershipSha256,
    required this.role,
    required this.venueId,
    required this.installationId,
    required this.deviceId,
    required this.hostId,
    required this.gatewayHostId,
    required this.authorityEpoch,
    required this.protocolVersion,
    required this.helperProtocolVersion,
    required this.databaseSchemaVersion,
    required this.minimumReaderVersion,
    required this.routeRevision,
    required this.configRevision,
    required this.registryRevision,
    required this.bindingRevision,
    required this.capabilityRevision,
    required this.capabilityProfileSha256,
    required this.hostBinarySha256,
    required this.helperBinarySha256,
  }) {
    if (![venueId, installationId, deviceId, hostId].every(printerAgentUuid) ||
        ![
          authorityEpoch,
          routeRevision,
          configRevision,
          registryRevision,
          bindingRevision,
          capabilityRevision,
        ].every(printerAgentRevision) ||
        ![
          capabilityProfileSha256,
          hostBinarySha256,
          helperBinarySha256,
        ].every(printerAgentDigest) ||
        protocolVersion != 1 ||
        helperProtocolVersion != 1 ||
        databaseSchemaVersion != 6 ||
        minimumReaderVersion != 2 ||
        !['posAgent', 'printGateway'].contains(role)) {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
    if (scope == PrinterAgentScope.local) {
      if (ownershipPolicy != 'localHost' ||
          gatewayHostId != hostId ||
          clusterId.isNotEmpty ||
          membershipSha256.isNotEmpty) {
        throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
      }
    } else if (!printerAgentUuid(clusterId) ||
        !printerAgentDigest(membershipSha256) ||
        (ownershipPolicy != 'clusterLogicalOnly' &&
            ownershipPolicy != 'qualifiedGateway') ||
        (ownershipPolicy == 'clusterLogicalOnly' && gatewayHostId.isNotEmpty) ||
        (ownershipPolicy == 'qualifiedGateway' &&
            !printerAgentUuid(gatewayHostId))) {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
  }

  final PrinterAgentScope scope;
  final String ownershipPolicy, clusterId, membershipSha256, role;
  final String venueId, installationId, deviceId, hostId, gatewayHostId;
  final int authorityEpoch, protocolVersion, helperProtocolVersion;
  final int databaseSchemaVersion, minimumReaderVersion;
  final int routeRevision, configRevision, registryRevision, bindingRevision;
  final int capabilityRevision;
  final String capabilityProfileSha256, hostBinarySha256, helperBinarySha256;

  Map<String, Object> toJson() => {
    'scope': scope == PrinterAgentScope.local ? 'LOCAL' : 'VENUE_SHARED',
    'ownershipPolicy': ownershipPolicy,
    'clusterId': clusterId,
    'membershipSha256': membershipSha256,
    'role': role,
    'venueId': venueId,
    'installationId': installationId,
    'deviceId': deviceId,
    'hostId': hostId,
    'gatewayHostId': gatewayHostId,
    'authorityEpoch': authorityEpoch,
    'protocolVersion': protocolVersion,
    'helperProtocolVersion': helperProtocolVersion,
    'databaseSchemaVersion': databaseSchemaVersion,
    'minimumReaderVersion': minimumReaderVersion,
    'routeRevision': routeRevision,
    'configRevision': configRevision,
    'registryRevision': registryRevision,
    'bindingRevision': bindingRevision,
    'capabilityRevision': capabilityRevision,
    'capabilityProfileSha256': capabilityProfileSha256,
    'hostBinarySha256': hostBinarySha256,
    'helperBinarySha256': helperBinarySha256,
  };

  factory PrinterAgentPins.fromJson(Map<String, dynamic> json) {
    const keys = {
      'scope',
      'ownershipPolicy',
      'clusterId',
      'membershipSha256',
      'role',
      'venueId',
      'installationId',
      'deviceId',
      'hostId',
      'gatewayHostId',
      'authorityEpoch',
      'protocolVersion',
      'helperProtocolVersion',
      'databaseSchemaVersion',
      'minimumReaderVersion',
      'routeRevision',
      'configRevision',
      'registryRevision',
      'bindingRevision',
      'capabilityRevision',
      'capabilityProfileSha256',
      'hostBinarySha256',
      'helperBinarySha256',
    };
    if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
    String string(String name) {
      final value = json[name];
      if (value is! String)
        throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
      return value;
    }

    int integer(String name) {
      final value = json[name];
      if (value is! int)
        throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
      return value;
    }

    final scope = switch (string('scope')) {
      'LOCAL' => PrinterAgentScope.local,
      'VENUE_SHARED' => PrinterAgentScope.venueShared,
      _ => throw const PrinterAgentException(
        PrinterAgentFailure.invalidProfile,
      ),
    };
    return PrinterAgentPins(
      scope: scope,
      ownershipPolicy: string('ownershipPolicy'),
      clusterId: string('clusterId'),
      membershipSha256: string('membershipSha256'),
      role: string('role'),
      venueId: string('venueId'),
      installationId: string('installationId'),
      deviceId: string('deviceId'),
      hostId: string('hostId'),
      gatewayHostId: string('gatewayHostId'),
      authorityEpoch: integer('authorityEpoch'),
      protocolVersion: integer('protocolVersion'),
      helperProtocolVersion: integer('helperProtocolVersion'),
      databaseSchemaVersion: integer('databaseSchemaVersion'),
      minimumReaderVersion: integer('minimumReaderVersion'),
      routeRevision: integer('routeRevision'),
      configRevision: integer('configRevision'),
      registryRevision: integer('registryRevision'),
      bindingRevision: integer('bindingRevision'),
      capabilityRevision: integer('capabilityRevision'),
      capabilityProfileSha256: string('capabilityProfileSha256'),
      hostBinarySha256: string('hostBinarySha256'),
      helperBinarySha256: string('helperBinarySha256'),
    );
  }

  bool matches(PrinterAgentPins other) {
    final a = toJson(), b = other.toJson();
    return a.keys.every((key) => a[key] == b[key]);
  }
}

/// Read-only explicit profile. Certificates are public pins; client secrets
/// are supplied separately in memory and never enter this object or Hive.
class PrinterAgentProfile {
  PrinterAgentProfile({
    required this.pins,
    required this.clientId,
    required this.currentDeviceInstallationId,
    required this.port,
    required List<int> pinnedServerCertificate,
  }) : _certificate = Uint8List.fromList(pinnedServerCertificate) {
    if (!printerAgentUuid(clientId) ||
        !printerAgentUuid(currentDeviceInstallationId) ||
        port < 1 ||
        port > 65535 ||
        _certificate.isEmpty ||
        _certificate.length > 16384) {
      throw const PrinterAgentException(PrinterAgentFailure.invalidProfile);
    }
  }
  final PrinterAgentPins pins;
  final String clientId;

  /// Explicit POS enrollment context, distinct from the Go service identity.
  /// Read-only comparison does not establish signed production authority.
  final String currentDeviceInstallationId;
  final int port;
  final Uint8List _certificate;
  Uint8List get pinnedServerCertificate => Uint8List.fromList(_certificate);
  String get expectedVenueId => pins.venueId;
  String get expectedDeviceId => pins.deviceId;
  String get expectedInstallationId => currentDeviceInstallationId;
  String get expectedAgentInstallationId => pins.installationId;
  String get expectedHostId => pins.hostId;
}

class PrinterAgentPrinterHold {
  PrinterAgentPrinterHold({
    required this.physicalPrinterId,
    required this.reason,
  }) {
    if (!printerAgentUuid(physicalPrinterId) ||
        reason.isEmpty ||
        reason.length > 512) {
      throw const PrinterAgentException(PrinterAgentFailure.protocolMismatch);
    }
  }
  final String physicalPrinterId, reason;
}

class PrinterAgentHealth {
  PrinterAgentHealth({
    required this.pins,
    required this.clientId,
    required this.state,
    required this.softwareReady,
    required Iterable<PrinterAgentHoldReason> holdReasons,
    Iterable<PrinterAgentPrinterHold> printerHolds = const [],
    this.activeAdmissions = 0,
  }) : holdReasons = List.unmodifiable(holdReasons),
       printerHolds = List.unmodifiable(printerHolds) {
    if (!printerAgentUuid(clientId) ||
        activeAdmissions < 0 ||
        activeAdmissions > printerAgentMaxInteger ||
        (softwareReady && state != PrinterAgentLifecycle.running) ||
        this.printerHolds.length > 64 ||
        this.printerHolds.map((h) => h.physicalPrinterId).toSet().length !=
            this.printerHolds.length ||
        this.holdReasons.toSet().length != this.holdReasons.length ||
        !this.holdReasons.contains(
          PrinterAgentHoldReason.provisioningUnqualified,
        ) ||
        !this.holdReasons.contains(
          PrinterAgentHoldReason.physicalActivationPending,
        ) ||
        (pins.scope == PrinterAgentScope.venueShared &&
            !this.holdReasons.contains(
              PrinterAgentHoldReason.sharedFenceUnqualified,
            ))) {
      throw const PrinterAgentException(PrinterAgentFailure.protocolMismatch);
    }
  }
  final PrinterAgentPins pins;
  final String clientId;
  final PrinterAgentLifecycle state;
  final bool softwareReady;
  final int activeAdmissions;
  final List<PrinterAgentHoldReason> holdReasons;
  final List<PrinterAgentPrinterHold> printerHolds;
  bool get physicalHeld => true;
  bool get admissionHeld => true;
  PrinterAgentScope get configuredScope => pins.scope;
}

abstract interface class PrinterAgentHealthReader {
  Future<PrinterAgentHealth> health();
}
