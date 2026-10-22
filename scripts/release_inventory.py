#!/usr/bin/env python3
"""Read locked release composition; never install, upgrade, execute scripts or scan by default."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit

NPM_PROJECTS = (
    'apps/backend', 'apps/platform-web', 'apps/restaurant-web',
    'apps/vankisi-custom-web', 'packages/website-client', 'templates/custom-site',
)
PUB_LOCKS = (
    'apps/operations/pubspec.lock', 'apps/devtool/pubspec.lock',
    'packages/contracts/generated/edge_dart/pubspec.lock',
    'apps/edge/tool/dart_sim/pubspec.lock',
)
GO_MODULES = ('apps/edge/go.mod', 'packages/contracts/generated/go/go.mod')
PUBLIC_GO_PREFIXES = (
    'golang.org/', 'google.golang.org/', 'go.etcd.io/', 'modernc.org/',
    'github.com/gofrs/', 'github.com/google/', 'github.com/hashicorp/',
    'github.com/boltdb/', 'github.com/fatih/', 'github.com/mattn/',
    'github.com/dustin/', 'github.com/ncruces/', 'github.com/remyoudompheng/',
)
VERSION = re.compile(r'^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')


class InventoryError(Exception):
    pass


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def clean_env():
    # Keep ordinary OS paths; do not forward registry tokens, proxies or config.
    return {key: value for key, value in os.environ.items()
            if key in ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL', 'USER', 'SYSTEMROOT')}


def public_url(value, hosts):
    if not isinstance(value, str):
        return False
    try:
        parsed = urlsplit(value)
        if parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise InventoryError('A dependency URL contains private or unreviewed fields')
        return parsed.scheme == 'https' and parsed.hostname in hosts
    except ValueError as error:
        raise InventoryError('Invalid dependency URL') from error


def npm_components(lock, project):
    if lock.get('lockfileVersion') not in (2, 3) or not isinstance(lock.get('packages'), dict):
        raise InventoryError('Only npm lockfile v2/v3 package maps are supported')
    root = lock['packages'].get('', {})
    direct_names = set(root.get('dependencies', {})) | set(root.get('devDependencies', {})) | set(root.get('optionalDependencies', {}))
    components = []
    for location, row in sorted(lock['packages'].items()):
        if not location or row.get('link'):
            continue  # The application and local workspace aliases never become queries.
        name = row.get('name') or location.rsplit('node_modules/', 1)[-1]
        version = row.get('version')
        if not isinstance(name, str) or not isinstance(version, str):
            raise InventoryError('A locked npm component has no name/version')
        registry = public_url(row.get('resolved'), {'registry.npmjs.org'})
        components.append({
            'ecosystem': 'npm', 'name': name, 'version': version,
            'project': project, 'location': location,
            'direct': any(location == f'node_modules/{key}' for key in direct_names),
            'developmentOnly': row.get('dev') is True,
            'optional': row.get('optional') is True or row.get('devOptional') is True,
            'queryEligible': registry and bool(VERSION.fullmatch(version)),
            'integrity': row.get('integrity'), 'license': row.get('license'),
        })
    return components


def yaml_json(path, pod=False):
    # Ruby's standard safe YAML parser avoids adding a Python dependency or
    # attempting to interpret the complete YAML grammar ourselves.
    symbols = ('permitted_classes: [Symbol], permitted_symbols: ["path", "podspec", "git", "tag", "branch", "commit"]'
               if pod else 'permitted_classes: [], permitted_symbols: []')
    command = ['ruby', '-ryaml', '-rjson', '-e',
               'puts JSON.generate(YAML.safe_load(File.read(ARGV.fetch(0)), ' + symbols + ', aliases: false))', str(path)]
    result = subprocess.run(command, env=clean_env(), capture_output=True, text=True)
    if result.returncode:
        raise InventoryError(f'Cannot safely parse YAML lockfile {Path(path).name}')
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise InventoryError('Lockfile must contain a mapping')
    return value


def pub_components(lock, project):
    packages = lock.get('packages')
    if not isinstance(packages, dict):
        raise InventoryError('Pub lockfile has no package map')
    components = []
    for name, row in sorted(packages.items()):
        version = row.get('version')
        if not isinstance(version, str):
            raise InventoryError('A locked Pub component has no version')
        description = row.get('description')
        hosted = row.get('source') == 'hosted' and isinstance(description, dict)
        public = hosted and public_url(description.get('url'), {'pub.dev', 'pub.dartlang.org'})
        components.append({
            'ecosystem': 'Pub', 'name': name, 'version': version,
            'project': project, 'source': row.get('source'),
            'direct': str(row.get('dependency', '')).startswith('direct '),
            'developmentOnly': (True if row.get('dependency') == 'direct dev' else
                                False if row.get('dependency') == 'direct main' else None),
            'queryEligible': bool(public and VERSION.fullmatch(version)),
            'checksum': description.get('sha256') if hosted else None,
        })
    return components


def go_components(module, project):
    local_replacements = {entry['Old']['Path'] for entry in module.get('Replace') or []
                          if not entry['New'].get('Version')}
    return [{
        'ecosystem': 'Go', 'name': entry['Path'], 'version': entry['Version'],
        'project': project, 'direct': not entry.get('Indirect', False),
        'developmentOnly': None,  # go.mod does not prove build/test reachability.
        'queryEligible': entry['Path'] not in local_replacements and
                         entry['Path'].startswith(PUBLIC_GO_PREFIXES) and
                         bool(VERSION.fullmatch(entry['Version'])),
        'localReplacement': entry['Path'] in local_replacements,
    } for entry in module.get('Require') or []]


def query_payload(components):
    unique = set()
    for row in components:
        if row.get('queryEligible'):
            name, version, ecosystem = row['name'], row['version'], row['ecosystem']
            if (ecosystem not in ('npm', 'Go', 'Pub') or
                    not isinstance(name, str) or not re.fullmatch(r'[@A-Za-z0-9_./+-]+', name) or
                    not isinstance(version, str) or not VERSION.fullmatch(version)):
                raise InventoryError('Invalid public dependency query')
            unique.add((ecosystem, name, version))
    return {'queries': [{'package': {'ecosystem': ecosystem, 'name': name}, 'version': version}
                        for ecosystem, name, version in sorted(unique)]}


def verify_inputs(repo, hashes):
    if any(digest(repo / name) != expected for name, expected in hashes.items()):
        raise InventoryError('Inputs changed during inventory; qualify a fresh snapshot')


def missing_runtime_direct(lock, bom):
    names = {row['name'] for row in bom.get('components', [])}
    missing = []
    for name in lock['packages'].get('', {}).get('dependencies', {}):
        row = lock['packages'].get(f'node_modules/{name}', {})
        if row.get('link'):
            continue
        if (row.get('name') or name) not in names:
            missing.append(name)
    return sorted(missing)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def inventory(repo, output, go, npm='npm'):
    repo, output = Path(repo).resolve(), Path(output).resolve()
    if output.exists():
        raise InventoryError('Use a fresh output directory; existing reports are preserved')
    output.mkdir(parents=True)
    components, hashes, projects, sboms = [], {}, [], []
    env = clean_env()
    with tempfile.TemporaryDirectory(prefix='release-inventory-') as temporary:
        scratch = Path(temporary)
        for config in ('user.npmrc', 'global.npmrc'):
            (scratch / config).write_text('')
        for project in NPM_PROJECTS:
            folder = scratch / project
            folder.mkdir(parents=True)
            for name in ('package.json', 'package-lock.json'):
                relative = f'{project}/{name}'
                hashes[relative] = digest(repo / relative)
                shutil.copyfile(repo / relative, folder / name)
            lock = json.loads((folder / 'package-lock.json').read_text())
            rows = npm_components(lock, project)
            components.extend(rows)
            projects.append({'project': project, 'ecosystem': 'npm', 'components': len(rows)})
            # Existing npm Arborist reads the lock and its standard CycloneDX emitter
            # writes the graph. Runtime scope uses node.dev flags, retaining
            # nodes shared by production and development (unlike CSS .dev).
            for scope in ('build', 'production'):
                name = project.replace('/', '-') + '-' + scope + '.cdx.json'
                npm_cli = Path(shutil.which(npm) or npm).resolve()
                npm_root = npm_cli.parent.parent
                command = ['node', str(Path(__file__).with_name('npm_lock_sbom.cjs')),
                           str(folder), str(npm_root), scope]
                result = subprocess.run(command, cwd=folder, env=env, capture_output=True, text=True)
                if result.returncode:
                    # The stderr is local evidence, not instructions, and not a public report.
                    (output / (name + '.stderr')).write_text(result.stderr)
                    sboms.append({'project': project, 'scope': scope, 'status': 'FAILED', 'exitCode': result.returncode})
                    continue
                bom = json.loads(result.stdout)
                if bom.get('bomFormat') != 'CycloneDX':
                    raise InventoryError('npm returned an unexpected SBOM format')
                (output / name).write_text(result.stdout)
                missing = missing_runtime_direct(lock, bom) if scope == 'production' else []
                sboms.append({'project': project, 'scope': scope,
                              'status': 'SCOPE_INCOMPLETE' if missing else 'PASS', 'file': name,
                              'sha256': digest(output / name), 'components': len(bom.get('components', [])),
                              'missingRuntimeDirectDependencies': missing})
        for relative in PUB_LOCKS:
            hashes[relative] = digest(repo / relative)
            rows = pub_components(yaml_json(repo / relative), relative)
            components.extend(rows)
            projects.append({'project': relative, 'ecosystem': 'Pub', 'components': len(rows)})
        for relative in GO_MODULES:
            hashes[relative] = digest(repo / relative)
            sum_file = str(Path(relative).with_name('go.sum'))
            hashes[sum_file] = digest(repo / sum_file)
            result = subprocess.run([go, 'mod', 'edit', '-json', str(repo / relative)],
                                    env={**env, 'GOTOOLCHAIN': 'local'}, capture_output=True, text=True)
            if result.returncode:
                raise InventoryError('Go could not read a module file')
            module = json.loads(result.stdout)
            rows = go_components(module, relative)
            components.extend(rows)
            projects.append({'project': relative, 'ecosystem': 'Go', 'components': len(rows), 'declaredGo': module.get('Go')})
        native = []
        for relative in ('apps/operations/macos/Podfile.lock', 'apps/operations/ios/Podfile.lock'):
            hashes[relative] = digest(repo / relative)
            lock = yaml_json(repo / relative, pod=True)
            native.append({'lockfile': relative, 'cocoaPods': lock.get('COCOAPODS'),
                           'declaredPods': lock.get('PODS', []), 'advisoryScan': 'NOT_RUN'})
        recipes = []
        for relative in ('apps/backend/Dockerfile', 'deploy/frontend.Dockerfile', 'compose.yaml', 'compose.local.yaml'):
            hashes[relative] = digest(repo / relative)
            for number, line in enumerate((repo / relative).read_text().splitlines(), 1):
                match = re.match(r'\s*(?:FROM\s+|image:\s*)(\S+)', line)
                if match:
                    recipes.append({'file': relative, 'line': number, 'reference': match.group(1),
                                    'digestPinned': '@sha256:' in match.group(1)})
    verify_inputs(repo, hashes)
    payload = query_payload(components)
    write_json(output / 'components.json', components)
    write_json(output / 'public-osv-queries.json', payload)
    report = {'formatVersion': 1, 'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'status': 'INVENTORIED' if all(b['status'] == 'PASS' for b in sboms) else 'PARTIAL_SBOM_FAILURE',
              'inputSha256': hashes, 'projects': projects, 'componentOccurrences': len(components),
              'publicUniqueQueries': len(payload['queries']), 'sboms': sboms, 'native': native,
              'containerRecipes': recipes, 'networkRequests': 0,
              'limitations': ['Lockfile composition is not installed-image or binary attestation',
                              'Advisory queries are prepared, not executed',
                              'Go/Pub transitive build/runtime reachability is not established',
                              'Go rows are declared requirements, not a resolved full MVS module graph',
                              'A runtime lock SBOM must retain shared prod/dev nodes and direct runtime dependencies',
                              'Container OS, SDK and native plugin advisories remain separate checks',
                              'No application source, environment, credentials or business data are query fields']}
    write_json(output / 'inventory.json', report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--go', default=shutil.which('go'))
    args = parser.parse_args()
    if not args.go:
        parser.error('Provide the existing Go SDK path with --go')
    try:
        report = inventory(args.repo, args.output, args.go)
    except (InventoryError, OSError, json.JSONDecodeError) as error:
        parser.exit(2, f'Inventory failed: {error}\n')
    print(json.dumps({'status': report['status'], 'projects': len(report['projects']),
                      'components': report['componentOccurrences'], 'publicQueries': report['publicUniqueQueries'],
                      'sbomsPassed': sum(b['status'] == 'PASS' for b in report['sboms']),
                      'sbomsFailed': sum(b['status'] != 'PASS' for b in report['sboms']), 'networkRequests': 0}))
    return 0 if report['status'] == 'INVENTORIED' else 1


if __name__ == '__main__':
    raise SystemExit(main())
