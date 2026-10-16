from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import subprocess

root = Path('/tmp/vynic-readiness-resume-20261006-uv9ayewl/software-completion')
source = root / 'source'
metadata = root / 'metadata'
owned = [
    'apps/edge/internal/printeragent/server.go',
    'apps/edge/internal/printeragent/server_test.go',
    'apps/edge/internal/printeragent/AUTHORITY_BRIDGE.md',
    'packages/contracts/proto/vynic/edge/v1/printer_agent.proto',
    'packages/contracts/generated/go/vynic/edge/v1/printer_agent.pb.go',
    'packages/contracts/generated/go/vynic/edge/v1/printer_agent_grpc.pb.go',
    'packages/contracts/generated/edge_dart/lib/src/generated/vynic/edge/v1/printer_agent.pb.dart',
    'packages/contracts/generated/edge_dart/lib/src/generated/vynic/edge/v1/printer_agent.pbenum.dart',
    'packages/contracts/generated/edge_dart/lib/src/generated/vynic/edge/v1/printer_agent.pbgrpc.dart',
    'packages/contracts/generated/edge_dart/lib/src/generated/vynic/edge/v1/printer_agent.pbjson.dart',
    'packages/contracts/generated/edge_dart/lib/vynic_edge_contracts.dart',
    'apps/operations/lib/core/services/printing/printer_agent_profile.dart',
    'apps/operations/lib/core/services/printing/printer_agent_client.dart',
    'apps/operations/test/unit/printer_agent_client_test.dart',
]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(name, value):
    path = metadata / name
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    return path

before = json.loads((metadata / 'printer-agent-before-hashes.json').read_text())
barrel = 'packages/contracts/generated/edge_dart/lib/vynic_edge_contracts.dart'
changed = {
    group: [path for path, digest in values.items() if sha(source / path) != digest]
    for group, values in before.items()
}
assert all(paths == [barrel] for paths in changed.values()), changed
guards = {'beforeManifestSha256': sha(metadata / 'printer-agent-before-hashes.json'),
          'observedChanges': changed,
          'permittedAdditiveBarrelExport': barrel,
          'allPreviousGeneratedOutputUnchanged': True,
          'sealedOriginalAndPreviousSourceEdited': False}
write('printer-agent-baseline-guard.json', guards)

checks = []
for relative in owned:
    result = subprocess.run(['git', 'diff', '--no-index', '--check', '/dev/null', str(source / relative)], capture_output=True, text=True)
    if result.returncode not in (0, 1) or result.stdout or result.stderr:
        raise RuntimeError((relative, result.returncode, result.stdout, result.stderr))
    checks.append({'path': relative, 'diagnostics': '', 'exitCode': result.returncode})
write('printer-agent-whitespace-check.json', {'result': 'PASS', 'files': checks,
      'note': 'No-index exit 1 means the new-file addition differs, not a whitespace error; every command has zero diagnostics.'})

manifest = write('printer-agent-owned-source-manifest.json', {
    'scope': 'AUTHENTICATED_LOOPBACK_HEALTH_ONLY_HELD_PROVISIONING',
    'sourceRoot': str(source), 'ownedFileCount': len(owned),
    'files': {relative: {'sha256': sha(source / relative), 'bytes': (source / relative).stat().st_size,
                         'beforeSha256': before['prior26'].get(relative),
                         'generated': relative != barrel and '/generated/' in relative}
              for relative in owned},
})

rows = [json.loads(line) for line in (metadata / 'printer-agent-distinct-installation-race.jsonl').read_text().splitlines()]
passes = [row for row in rows if row.get('Action') == 'pass' and row.get('Test')]
skips = [row['Test'] for row in rows if row.get('Action') == 'skip' and row.get('Test')]
assert len(passes) == 37
assert not any(row.get('Action') == 'fail' for row in rows)
assert skips == ['TestPrinterAgentProcess']
assert 'All tests passed!' in (metadata / 'printer-agent-distinct-installation-dart-test.log').read_text()
assert 'No issues found!' in (metadata / 'printer-agent-final-three-analysis-qualified.log').read_text()
assert (metadata / 'printer-agent-final-generation-check.log').stat().st_size == 0
assert (metadata / 'printer-agent-final-vet.log').stat().st_size == 0
assert (metadata / 'printer-agent-windows-fixture-build.log').stat().st_size == 0

log_names = [
    'printer-agent-distinct-installation-race.jsonl',
    'printer-agent-distinct-installation-race.stderr',
    'printer-agent-distinct-installation-dart-test.log',
    'printer-agent-final-three-analysis-qualified.log',
    'printer-agent-final-format.log',
    'printer-agent-final-vet.log',
    'printer-agent-generation.log',
    'printer-agent-final-generation-check.log',
    'printer-agent-distinct-installation-fixture-build.log',
    'printer-agent-windows-fixture-build.log',
    'printer-agent-darwin-buildinfo.log',
    'printer-agent-windows-buildinfo.log',
    'printer-agent-baseline-guard.json',
    'printer-agent-whitespace-check.json',
]
generation = write('printer-agent-generation-receipt.json', {
    'canonicalScript': 'packages/contracts/scripts/generate-edge.sh',
    'tools': {'protoc': '36.2', 'protoc-gen-go': '1.36.11',
              'protoc-gen-go-grpc': '1.6.2', 'protoc_plugin': '25.0.0'},
    'generatedOutputCount': 6,
    'generatedOutputSha256': {name: sha(source / name) for name in owned if name != barrel and '/generated/' in name},
    'handEditedGeneratedFiles': False,
    'freshCanonicalCheck': {'exitCode': 0, 'log': 'printer-agent-final-generation-check.log',
                            'sha256': sha(metadata / 'printer-agent-final-generation-check.log')},
    'previousGeneratedFilesUnchanged': True,
    'additiveNongeneratedBarrelExport': barrel,
})

backend_root = Path('/Users/vaanskii/Developer/vynic')
inspected_backend = ['apps/backend/src/auth/device-credential.service.ts',
                     'apps/backend/src/edge/device-enrollment.service.ts',
                     'apps/backend/src/edge-foundation/edge-foundation.ts',
                     'apps/backend/src/customer/printer-runtime-config.ts',
                     'apps/backend/src/customer/printer-runtime-persistence.ts']

receipt = write('printer-agent-validation-receipt.json', {
    'createdAt': datetime.now(timezone.utc).isoformat(),
    'result': 'PASS_BOUNDED_HELD_SOFTWARE',
    'ownedManifest': manifest.name, 'ownedManifestSha256': sha(manifest),
    'generationReceipt': generation.name, 'generationReceiptSha256': sha(generation),
    'validation': {
        'goRace': {'command': 'GOPROXY=off go test -mod=readonly -race -count=1 -json ./internal/printeragent',
                   'workingDirectory': 'apps/edge', 'exitCode': 0, 'topLevelPassed': 7,
                   'passedTestRecords': len(passes), 'packagePassRecords': 1,
                   'skip': skips, 'skipMeaning': 'Child-process entry runs in the actual Dart/UI fixture; deliberately skipped when no fixture directory is provided.',
                   'failRecords': 0, 'raceFindings': 0},
        'dart': {'command': 'flutter --suppress-analytics test --no-pub test/unit/printer_agent_client_test.dart',
                 'workingDirectory': 'apps/operations',
                 'environment': {'VYNIC_PRINTER_AGENT_GO_FIXTURE': str(root / 'tools/printer-agent-server.test')},
                 'passed': 23, 'exitCode': 0,
                 'actualChildGoProcessMutualTLS': True, 'unequalPosAndGoInstallationUUIDs': True},
        'analysis': {'files': owned[-3:], 'exitCode': 0, 'issues': 0},
        'format': {'files': 3, 'changed': 0, 'exitCode': 0},
        'goVet': {'command': 'GOPROXY=off go vet -mod=readonly ./internal/printeragent', 'exitCode': 0},
        'windowsBuild': {'command': 'GOPROXY=off GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go test -c -mod=readonly -o tools/printer-agent-server-windows.test.exe ./internal/printeragent',
                         'exitCode': 0, 'executionClaim': 'Cross-compiled only; no Windows execution claimed by this receipt.'},
        'whitespace': {'files': len(owned), 'diagnostics': 0},
        'generationCheck': {'exitCode': 0, 'diff': ''},
    },
    'artifacts': {name: {'sha256': sha(root / 'tools' / name), 'bytes': (root / 'tools' / name).stat().st_size}
                  for name in ['printer-agent-server.test', 'printer-agent-server-windows.test.exe']},
    'logs': {name: {'sha256': sha(metadata / name), 'bytes': (metadata / name).stat().st_size} for name in log_names},
    'claims': {
        'tlsVersion': '1.3', 'fixtureCertificateAlgorithm': 'ECDSA_P256',
        'fixtureCredentials': 'Ephemeral temporary test files only; no installation or real credential issuance.',
        'candidateGrantAlgorithm': 'Ed25519, separate from transport certificates; validation-only optional seam.',
        'signedProductionAuthority': False, 'physicalDispatch': 'HELD', 'admission': 'HELD_PROVISIONING',
        'successfulReceipts': 0, 'heldSubmitQueueWrites': 0,
        'queueTablesAssertedZero': ['pq_job', 'pq_receipt', 'pq_claim', 'pq_attempt', 'pq_beep'],
        'normalStartupAttachment': False, 'proofAuthorityPromotion': False,
        'physicalJobsPerformed': 0, 'SCMRegistrationPerformed': False,
        'originInterpretation': 'currentDeviceInstallationId is readonly POS enrollment context, distinct from pins.installationId; neither grants production terminal/origin authority.',
        'productionAdmissionBlocker': 'Missing real printer-only issuer, signed Device/Venue/both-installations/terminal/origin certificate registration, protected persisted high-water/revocation freshness source and authoritative physical route/cutover bridge.',
        'candidateSourceOwnership': 'Separate printerprovisioning agent; this receipt qualifies the held server interface, not production authority or that package independently.',
        'serviceCLIInstallerUIOwnership': 'Separate agents; final integrated source/test snapshot required.',
        'priorSealedSourceEdited': False,
    },
    'retainedInitialDiagnostics': ['printer-agent-dart-first-test.log', 'printer-agent-tls-diagnostic-dart.log',
        'printer-agent-tls-diagnostic-go.log', 'printer-agent-first-vet-wrong-workdir.log',
        'printer-agent-final-three-analysis.log'],
    'diagnosticResolution': 'Initial Ed25519 fixture TLS was unsupported by actual Dart3.12; P-256 fixture now passes. Initial analyzer sandbox timestamp and earlier wrong vet cwd are retained; scoped successful reruns are the cited final evidence.',
    'readOnlyBackendEvidence': {name: sha(backend_root / name) for name in inspected_backend},
})

print(json.dumps({'ownedFiles': len(owned), 'manifest': str(manifest), 'manifestSha256': sha(manifest),
                  'receipt': str(receipt), 'receiptSha256': sha(receipt),
                  'generationReceiptSha256': sha(generation)}, indent=2))
