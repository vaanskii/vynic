"""Freeze the explicitly owned software completion candidate for final checks."""
import datetime
import hashlib
import json
import pathlib
import shutil

task = pathlib.Path(__file__).resolve().parent
source = task / 'source-v2'
target = task / 'final-cohort-v2'
output = task / 'verification/final-cohort-v2-source.json'
parts = ['apps/edge', 'apps/operations', 'packages/contracts/generated/go',
         'packages/contracts/generated/edge_dart', 'packages/contracts/proto']
ignored = {'node_modules', '.dart_tool', 'build', '.git', 'dist', 'Pods',
           '.symlinks', 'ephemeral', '.plugin_symlinks', '__pycache__'}
ignored_names = {'.flutter-plugins', '.flutter-plugins-dependencies', '.DS_Store'}

def selected(base):
    result = {}
    for part in parts:
        for path in sorted((base / part).rglob('*')):
            relative = path.relative_to(base)
            if (path.is_file() and not path.is_symlink()
                    and not ignored.intersection(relative.parts)
                    and path.name not in ignored_names):
                raw = path.read_bytes()
                result[str(relative)] = {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)}
    return result

if target.exists() or output.exists():
    raise SystemExit('Existing final evidence must be preserved; explicitly create another cohort')
before = selected(source)
for name in before:
    destination = target / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, destination)
if selected(target) != before or selected(source) != before:
    raise SystemExit('Source changed during snapshot; do not qualify this cohort')
metadata = target / 'apps/operations/.dart_tool'
metadata.mkdir()
for name in ('package_config.json', 'package_graph.json'):
    shutil.copyfile(source / 'apps/operations/.dart_tool' / name, metadata / name)
hooks = source / 'apps/operations/.dart_tool/hooks_runner'
if hooks.exists():
    shutil.copytree(hooks, metadata / 'hooks_runner')
earlier = task.parent / 'printer-validation'
tests = json.loads((earlier / 'flutter-final-test-selection.json').read_text())
tests += ['test/unit/printer_agent_client_test.dart',
          'test/unit/printer_agent_runtime_profile_test.dart',
          'test/widget/printer_agent_status_card_test.dart']
analysis = json.loads((earlier / 'flutter-final-analysis-selection.json').read_text())
analysis += ['lib/core/services/printing/printer_agent_client.dart',
             'lib/core/services/printing/printer_agent_profile.dart',
             'lib/core/services/printing/printer_agent_runtime_profile.dart',
             'lib/apps/windows_pos/widgets/admin/printers/printer_agent_status_card.dart',
             'lib/apps/windows_pos/widgets/admin/printers/admin_printers_section.dart',
             'lib/core/services/edge/edge_device_credential_store.dart',
             'test/unit/printer_agent_client_test.dart',
             'test/unit/printer_agent_runtime_profile_test.dart',
             'test/widget/printer_agent_status_card_test.dart',
             'test/support/printer_agent_status_fixture.dart']
tests, analysis = sorted(set(tests)), sorted(set(analysis))
for name in tests + analysis:
    if not (target / 'apps/operations' / name).is_file():
        raise SystemExit('Missing declared validation input: ' + name)
receipt = {
    'createdAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baseCommit': '275688e1e5c5dc0e26e62705ab0c7670cf16d99a',
    'source': str(source), 'snapshot': str(target), 'parts': parts,
    'beforeCopyAfterEqual': True, 'fileCount': len(before), 'files': before,
    'testSelection': tests, 'analysisSelection': analysis,
    'sourcePolicy': 'Isolated HEAD export + previously sealed owned printer inputs + reviewed software completion; original unrelated WIP excluded',
    'originalWorkspaceQualified': False, 'exactCommittedRuntimeQualified': False,
}
output.write_text(json.dumps(receipt, indent=2) + '\n')
for name, data in [('final-flutter-v2-test-selection.json', tests), ('final-flutter-v2-analysis-selection.json', analysis)]:
    (output.parent / name).write_text(json.dumps(data, indent=2) + '\n')
print(json.dumps({'files': len(before), 'suites': len(tests), 'analysis': len(analysis), 'receipt': str(output)}))
