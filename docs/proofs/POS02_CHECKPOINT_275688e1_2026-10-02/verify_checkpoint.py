"""Read-only integrity check for the paused POS-02 candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-working-tree', action='store_true')
    args = parser.parse_args()
    checkpoint = Path(__file__).resolve().parent
    manifest = json.loads((checkpoint / 'CHECKSUMS.json').read_text())
    for name, expected in manifest['checkpointFilesSha256'].items():
        assert digest((checkpoint / name).read_bytes()) == expected, name

    sources = json.loads((checkpoint / 'candidate-source-sha256.json').read_text())
    with tarfile.open(checkpoint / 'candidate-source.tar.gz', 'r:gz') as archive:
        members = archive.getmembers()
        assert all(m.isfile() and not Path(m.name).is_absolute()
                   and '..' not in Path(m.name).parts for m in members)
        actual = {m.name: digest(archive.extractfile(m).read()) for m in members}
        assert len(actual) == len(members), 'Duplicate archive paths'
        assert actual == sources, 'Candidate source archive identity mismatch'

    proof = json.loads((checkpoint / 'evidence/POS02_CANDIDATE_275688e1_2026-10-02.json').read_text())
    for name, expected in proof['candidateRuntimeAndContractInputSha256'].items():
        assert sources[name] == expected, name
    native = json.loads((checkpoint / 'evidence/POS02_NATIVE_275688e1_2026-10-02.json').read_text())
    for name, expected in native['sourceSha256'].items():
        assert sources['apps/operations/' + name] == expected, name
    for name, expected in proof['acceptance']['suiteSha256'].items():
        assert sources[name] == expected, name

    logs = json.loads((checkpoint / 'log-entry-sha256.json').read_text())
    with zipfile.ZipFile(checkpoint / 'evidence/POS02_LOGS_275688e1_2026-10-02.zip') as archive:
        assert archive.testzip() is None, 'Log archive CRC failure'
        assert {name: digest(archive.read(name)) for name in archive.namelist()} == logs

    if args.check_working_tree:
        root = checkpoint.parents[2]
        for name, expected in proof['taskSha256'].items():
            assert digest((root / name).read_bytes()) == expected, name
        baseline = json.loads((checkpoint / 'baseline-preservation.json').read_text())
        task_docs = set(proof['preservation']['targetedOriginalWIPDocUpdates'])
        for entry in baseline['entries']:
            if entry['path'] not in task_docs:
                assert digest((root / entry['path']).read_bytes()) == entry['sha256'], entry['path']

    print(json.dumps({
        'status': 'PASS', 'checkpointFiles': len(manifest['checkpointFilesSha256']),
        'candidateSourceFiles': len(sources), 'verifiedNativeSourceBindings': len(native['sourceSha256']),
        'verifiedAcceptanceSuites': len(proof['acceptance']['suiteSha256']),
        'verifiedLogEntries': len(logs), 'workingTreeChecked': args.check_working_tree,
        'milestoneDone': False, 'dependentWork': 'PAUSED_PENDING_USER_DECISIONS',
    }, indent=2))


if __name__ == '__main__':
    main()
