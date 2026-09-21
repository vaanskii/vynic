#!/usr/bin/env python3
"""Run either macOS development product with hot reload on the shared source."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from product import prepare


def link(path, target):
    if path.is_symlink():
        path.unlink()
    elif path.exists():
        raise RuntimeError(f'Expected a source symlink at {path}')
    path.symlink_to(target, target_is_directory=True)


def workspace(product):
    source = Path(__file__).resolve().parents[1]
    repository = source.parents[1]
    # Mirror the repository layout so pubspec's relative path dependencies
    # (../../packages/...) resolve unchanged, as they do in release staging.
    root = source / '.dart_tool' / 'vynic-dev' / product
    destination = root / 'apps' / 'operations'
    # Refresh source/native configuration but preserve each product's build cache.
    with tempfile.TemporaryDirectory(prefix='vynic-dev-') as temporary:
        staged = prepare(product, Path(temporary) / product)
        shutil.rmtree(staged / 'lib')
        shutil.copytree(staged, destination, dirs_exist_ok=True)
    link(destination / 'lib', source / 'lib')
    link(root / 'packages', repository / 'packages')
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('product', choices=['pos', 'manager'])
    parser.add_argument('--prepare-only', action='store_true')
    args, flutter_args = parser.parse_known_args()
    if any(arg in ('--release', '--profile') or arg.startswith('--dart-define=VYNIC_ENV=')
           for arg in flutter_args):
        parser.error('These shortcuts are for debug development only')
    if not args.prepare_only:
        label = 'Vynic Manager' if args.product == 'manager' else 'Vynic POS'
        print(f'Preparing {label} for macOS development (lib/main_{args.product}.dart)…',
              flush=True)
    destination = workspace(args.product)
    if args.prepare_only:
        print(destination)
        return
    command = ['flutter', 'run', '-d', 'macos', '--debug',
               '-t', f'lib/main_{args.product}.dart',
               '--dart-define=VYNIC_ENV=development',
               # Opens the POS developer panel without a token; see DeveloperAccess.
               '--dart-define=VYNIC_DEVELOPER_UNLOCK=true']
    if os.environ.get('VYNIC_DEV_API_URL'):
        command.append(f"--dart-define=VYNIC_API_URL={os.environ['VYNIC_DEV_API_URL']}")
    raise SystemExit(subprocess.call(command + flutter_args, cwd=destination))


if __name__ == '__main__':
    main()
