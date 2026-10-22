#!/usr/bin/env python3
"""Run Flutter tests with real, isolated Go wire fixtures; never use live services."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--go', default=os.environ.get('VYNIC_TEST_GO') or shutil.which('go'))
    parser.add_argument('--flutter', default=shutil.which('flutter'))
    args, tests = parser.parse_known_args()
    if not args.go or not args.flutter:
        parser.error('Provide installed Go and Flutter paths with --go and --flutter')
    source = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='vynic-flutter-wire-') as directory:
        root = Path(directory)
        env = {**os.environ, 'GOCACHE': str(root / 'go-cache'), 'GOTOOLCHAIN': 'local'}
        fixtures = {
            'VYNIC_PRINTER_AGENT_GO_FIXTURE': ('printeragent.test', './internal/printeragent'),
            'VYNIC_OPERATIONAL_PROOF_GO_FIXTURE': ('operationalproof.test', './internal/server'),
        }
        for key, (name, package) in fixtures.items():
            binary = root / name
            subprocess.run([args.go, 'test', '-c', '-o', str(binary), package], cwd=source.parent / 'edge', env=env, check=True)
            env[key] = str(binary)
        command = [args.flutter, 'test', *tests]
        return subprocess.run(command, cwd=source, env=env).returncode


if __name__ == '__main__':
    raise SystemExit(main())
