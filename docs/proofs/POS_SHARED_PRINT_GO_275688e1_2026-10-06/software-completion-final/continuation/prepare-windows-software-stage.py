"""Prepare fresh Windows software evidence, without invoking a VM or a build.

Execution is separately held after the recorded approval-review rejection.
Only the final frozen cohort and explicitly provided compiled test fixtures
can be staged. Existing proof directories and source inputs are preserved.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import runpy
import shutil
import uuid
import zipfile

TASK = pathlib.Path(__file__).resolve().parent
PROOF = pathlib.Path('/Users/vaanskii/Developer/vynic/docs/proofs/POS_SHARED_PRINT_GO_275688e1_2026-10-06')
IGNORED = {'build', '.dart_tool', '__pycache__', 'ephemeral'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def verify(source, files):
    for name, expected in files.items():
        parts = pathlib.PurePosixPath(name).parts
        if name.startswith('/') or '..' in parts or '\\' in name:
            raise SystemExit('Noncanonical frozen input')
        path = source / name
        if path.is_symlink() or digest(path) != expected['sha256'] or path.stat().st_size != expected['bytes']:
            raise SystemExit('Frozen input changed: ' + name)


def archive(source, files, target):
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as output:
        for name in sorted(files):
            output.write(source / name, name)
    with zipfile.ZipFile(target) as output:
        assert sorted(output.namelist()) == sorted(files)
        for name in files:
            assert hashlib.sha256(output.read(name)).hexdigest() == files[name]['sha256']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--operational-fixture', type=pathlib.Path, required=True)
    parser.add_argument('--agent-fixture', type=pathlib.Path, required=True)
    args = parser.parse_args()
    receipt_path = TASK / 'verification/final-cohort-source.json'
    receipt = json.loads(receipt_path.read_text())
    source = pathlib.Path(receipt['snapshot'])
    files = receipt['files']
    if source != TASK / 'final-cohort' or receipt['fileCount'] != len(files):
        raise SystemExit('Exact task-owned final cohort required')
    verify(source, files)
    fixtures = {'operational-proof-server-windows.test.exe': args.operational_fixture.resolve(),
                'printer-agent-server-windows.test.exe': args.agent_fixture.resolve()}
    for name, path in fixtures.items():
        if not path.is_relative_to(TASK) or path.is_symlink() or not path.is_file():
            raise SystemExit('Task-owned compiled test fixture required: ' + name)
        raw = path.read_bytes()
        offset = int.from_bytes(raw[60:64], 'little')
        if raw[:2] != b'MZ' or raw[offset:offset + 6] != b'PE\x00\x00\x64\x86':
            raise SystemExit('Cached windows/amd64 PE test fixture required')
    generic = PROOF / 'software-windows-flutter-stage'
    prepared_stage = PROOF / 'software-windows-pos-stage'
    prepared = TASK / 'windows-pos-prepared-source'
    for path in (generic, prepared_stage, prepared,
                 PROOF / 'software-windows-flutter-result', PROOF / 'software-windows-pos-result'):
        if path.exists():
            raise SystemExit('Preserve existing source/evidence: ' + str(path))
    prepare = runpy.run_path(str(source / 'apps/operations/tool/product.py'),
                            run_name='vynic_frozen_product_prepare')['prepare']
    prepare('pos', prepared / 'apps/operations')
    for name in files:
        if name == 'apps/operations/data/menu.json':
            continue
        destination = prepared / name
        if not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / name, destination)
    prepared_files = {str(path.relative_to(prepared)): {'sha256': digest(path), 'bytes': path.stat().st_size}
                      for path in sorted(prepared.rglob('*')) if path.is_file()}
    deltas = [{'path': name, 'before': files.get(name), 'after': prepared_files.get(name)}
              for name in sorted(set(files) | set(prepared_files))
              if files.get(name) != prepared_files.get(name)]
    allowed = {'apps/operations/lib/main.dart', 'apps/operations/pubspec.yaml',
               'apps/operations/data/menu.json', 'apps/operations/product-identity.json',
               'apps/operations/windows/CMakeLists.txt', 'apps/operations/windows/runner/main.cpp',
               'apps/operations/windows/runner/Runner.rc',
               'apps/operations/macos/Runner/Configs/AppInfo.xcconfig'}
    if {d['path'] for d in deltas} != allowed:
        raise SystemExit('Unexpected official product preparation delta')
    old = json.loads((PROOF / 'windows-pos-prepared-stage/stage-receipt.json').read_text())
    nonce = uuid.uuid4().hex[:12]
    for directory, tree, manifest in ((generic, source, files),
                                      (prepared_stage, prepared, prepared_files)):
        directory.mkdir()
        archive(tree, manifest, directory / 'source.zip')
        write(directory / 'source-manifest.json', manifest)
        write(directory / 'test-selection.json', receipt['testSelection'])
        write(directory / 'analysis-selection.json', receipt['analysisSelection'])
        for name, path in fixtures.items():
            shutil.copyfile(path, directory / name)
        values = {'schema': 1, 'createdAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'finalSourceReceiptSHA256': digest(receipt_path), 'files': len(manifest),
                  'sourceZipSHA256': digest(directory / 'source.zip'),
                  'sourceManifestSHA256': digest(directory / 'source-manifest.json'),
                  'testSuites': len(receipt['testSelection']), 'analysisFiles': len(receipt['analysisSelection']),
                  'fixtures': {name: {'sha256': digest(path), 'bytes': path.stat().st_size}
                               for name, path in fixtures.items()},
                  'firebaseSdk': old['firebaseSdk'], 'firebaseVersion': old['firebaseVersion'],
                  'firebaseVersionHeaderSha256': old['firebaseVersionHeaderSha256'],
                  'guestJobSuffix': 'VynicReadinessNative/software-' + nonce +
                                    ('-pos' if directory == prepared_stage else '-flutter'),
                  'executionStatus': 'HELD_AFTER_AUTOMATIC_APPROVAL_REJECTION',
                  'physicalJobs': 0, 'productStarted': False, 'serviceOperations': False,
                  'sourceScope': 'Exact new software cohort; previous898/535 receipts remain immutable'}
        write(directory / 'stage-receipt.json', values)
    write(prepared_stage / 'product-preparation.json', {
        'tool': 'apps/operations/tool/product.py::prepare(pos)',
        'toolSHA256': digest(source / 'apps/operations/tool/product.py'),
        'sourceReceiptSHA256': digest(receipt_path), 'deltas': deltas,
        'genericFiles': len(files), 'preparedFiles': len(prepared_files),
        'sourceBeforeAfterVerified': True, 'noBuildOrVMExecuted': True})
    verify(source, files)
    write(TASK / 'verification/windows-software-stage-preparation.json', {
        'genericStage': str(generic), 'posStage': str(prepared_stage),
        'finalSourceReceiptSHA256': digest(receipt_path),
        'genericStageReceiptSHA256': digest(generic / 'stage-receipt.json'),
        'posStageReceiptSHA256': digest(prepared_stage / 'stage-receipt.json'),
        'productPreparationSHA256': digest(prepared_stage / 'product-preparation.json'),
        'VMExecuted': False, 'executionHeld': True})
    print(json.dumps({'genericStage': str(generic), 'posStage': str(prepared_stage),
                      'files': len(files), 'preparationChanges': len(deltas), 'VMExecuted': False}))


if __name__ == '__main__':
    main()
