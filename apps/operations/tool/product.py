#!/usr/bin/env python3
"""Deterministic product builds with isolated native metadata; one Dart source tree."""
import argparse,json,os,shutil,subprocess,sys
from pathlib import Path
from urllib.parse import urlparse

def prepare(product, destination):
    source=Path(__file__).resolve().parents[1]
    destination=Path(destination)
    if destination.exists(): raise RuntimeError('Use a new output directory; existing output is never overwritten')
    destination.mkdir(parents=True)
    for name in ['lib','assets','data','windows','macos','android','ios']:
        shutil.copytree(source/name,destination/name,ignore=shutil.ignore_patterns('.env*','ephemeral','.gradle','build','Pods','.symlinks','local.properties','key.properties','*.jks','*.keystore','*.p12','*.mobileprovision'))
    for name in ['pubspec.yaml','pubspec.lock','analysis_options.yaml']:
        shutil.copyfile(source/name,destination/name)
    manifest=destination/'pubspec.yaml'
    manifest.write_text(manifest.read_text().replace('    - data/menu.json\n',''))
    (destination/'data/menu.json').unlink(missing_ok=True)
    (destination/'lib/main.dart').write_text(f"export 'main_{product}.dart';\n")
    label='Vynic POS' if product=='pos' else 'Vynic Manager'
    binary='vynic_pos' if product=='pos' else 'vynic_manager'
    identity='ge.vynic.pos' if product=='pos' else 'ge.vynic.manager'
    p=destination/'windows/CMakeLists.txt';s=p.read_text();s=s.replace('set(BINARY_NAME "vynic_manager")',f'set(BINARY_NAME "{binary}")');p.write_text(s)
    for relative in ['windows/runner/main.cpp','windows/runner/Runner.rc']:
        p=destination/relative;s=p.read_text().replace('Vynic Manager',label).replace('vynic_manager',binary).replace('ge.vynic.manager',identity);p.write_text(s)
    (destination/'product-identity.json').write_text(json.dumps({'product':label,'windowsApplicationId':identity,'binary':binary,'entrypoint':f'main_{product}.dart'},indent=2))
    return destination

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['build','run','prepare']);p.add_argument('product',choices=['pos','manager']);p.add_argument('platform',choices=['windows','macos','android','ios']);p.add_argument('--environment',choices=['development','staging','production'],default='development');p.add_argument('--api-url');p.add_argument('--output',required=True);p.add_argument('--device');p.add_argument('--no-codesign',action='store_true');args=p.parse_args()
    if args.product=='pos' and args.platform!='windows':p.error('Vynic POS supports Windows only')
    if args.action=='build' and args.environment=='development':p.error('Build requires staging or production; use run for development')
    if args.environment!='development':
        u=urlparse(args.api_url or '')
        if u.scheme!='https' or not u.hostname or u.username or u.query or u.fragment or u.path not in ('','/'):p.error('Provide the established HTTPS API origin with --api-url')
    if args.action=='build' and args.environment=='production' and args.platform=='android':
        for key in ['VYNIC_ANDROID_KEYSTORE','VYNIC_ANDROID_STORE_PASSWORD','VYNIC_ANDROID_KEY_ALIAS','VYNIC_ANDROID_KEY_PASSWORD']:
            if not os.environ.get(key):p.error(f'Production Android signing requires {key}')
    if args.no_codesign and args.platform!='ios':p.error('--no-codesign is only valid for iOS')
    destination=prepare(args.product,args.output)
    if args.action=='prepare':print(destination);return
    flutter=shutil.which('flutter')
    if not flutter:p.error('Flutter SDK not found on PATH')
    subprocess.run([flutter,'pub','get'],cwd=destination,check=True)
    command=[flutter,args.action]
    if args.action=='build':command += [{'android':'apk','ios':'ios'}.get(args.platform,args.platform),'--release']
    else:command += ['-d',args.device or args.platform]
    command += [f'--dart-define=VYNIC_ENV={args.environment}']
    if args.api_url:command += [f'--dart-define=VYNIC_API_URL={args.api_url}']
    if args.no_codesign:command += ['--no-codesign']
    subprocess.run(command,cwd=destination,check=True)
    # .env must never be an asset, even if a developer has one next to the source.
    leaked=list(destination.glob('build/**/flutter_assets/.env*'))
    if leaked:raise RuntimeError('Forbidden environment asset in build')
if __name__=='__main__':main()
