import hashlib
import json
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parent
source = root / 'source'
operations = source / 'apps/operations'
suites = json.loads((root / 'integrated-readiness-test-selection.json').read_text())
analysis = json.loads((root / 'integrated-readiness-analysis-selection.json').read_text())

def source_hashes():
    paths = list((operations / 'lib').rglob('*.dart'))
    paths += list((operations / 'test').rglob('*.dart'))
    paths += list((operations / 'tool').rglob('*.dart'))
    paths += list((operations / 'windows').rglob('*.cpp'))
    paths += list((operations / 'windows').rglob('*.h'))
    paths += list((operations / 'windows').rglob('CMakeLists.txt'))
    paths += list((source / 'packages/contracts/dart/lib').rglob('*.dart'))
    paths += [operations / 'pubspec.yaml', operations / 'pubspec.lock']
    return {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(paths)) if p.is_file()}

before = source_hashes()
results = []
for label, args in [
    ('tests', ['/opt/homebrew/bin/flutter', 'test', '--no-pub', '--reporter', 'expanded', *suites]),
    ('analysis', ['/opt/homebrew/bin/flutter', 'analyze', '--no-pub', *analysis]),
    ('format', ['/opt/homebrew/bin/dart', 'format', '--output=none', '--set-exit-if-changed', *analysis]),
]:
    path = root / ('integrated-readiness-' + label + '.log')
    with path.open('w') as log:
        result = subprocess.run(args, cwd=operations, stdout=log, stderr=subprocess.STDOUT)
    results.append({'label': label, 'command': args, 'exitCode': result.returncode,
                    'log': path.name, 'logSha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    print(label, result.returncode, flush=True)
    if result.returncode:
        print(path.read_text()[-5000:], flush=True)
after = source_hashes()
receipt = {'mode': 'UNCOMMITTED_ISOLATED_SOURCE_CANDIDATE', 'milestone': 'NOT_DONE',
           'tests': results, 'suites': suites, 'analysisFiles': analysis,
           'sourceUnchanged': before == after, 'sourceHashes': after,
           'sourceFiles': len(after), 'sourceChangedDuringVerification':
             sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p)),
           'windowsNativeBuild': 'PENDING_NOT_RUN', 'physicalPrinter': 'PENDING_NOT_RUN',
           'productionCoordinatorAttached': False, 'realLanProof': 'PENDING_NOT_RUN'}
(root / 'integrated-readiness-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: receipt[k] for k in ('milestone', 'sourceFiles', 'sourceUnchanged', 'sourceChangedDuringVerification')}), flush=True)
raise SystemExit(0 if before == after and all(r['exitCode'] == 0 for r in results) else 1)
