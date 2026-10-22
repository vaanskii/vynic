#!/usr/bin/env python3
"""Native MENU09 proof against a newly owned disposable PostgreSQL cluster."""
import argparse, json, os, re, shutil, subprocess, tempfile, time
from pathlib import Path
from urllib.parse import urlparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--environment', required=True, type=Path)
parser.add_argument('--flutter', required=True, type=Path)
args = parser.parse_args()
e = json.loads(args.environment.read_text())
p = Path(e['folder'])
url = e['urls']['fresh']
u = urlparse(url)
assert u.hostname == '127.0.0.1' and re.fullmatch('/disposable_menu09_[a-z0-9_]+', u.path)
assert str(p).startswith('/private/tmp/vynic-menu09-') and e['cluster'] == str(p / 'pg')
assert any(d['name'] == u.path[1:] and d['absentBefore'] and d['verificationOwned'] for d in e['databases'])
root = Path(tempfile.mkdtemp(prefix='vynic_menu09_process_', dir='/private/tmp'))
fixture = p / ('native-fixture-' + str(os.getpid()) + '.json')
assert not fixture.exists()
operations = Path(__file__).resolve().parents[1]
backend = operations.parent / 'backend'
env = {**os.environ, 'MENU09_TEST_DATABASE_URL': url, 'MENU09_HTTP_FIXTURE': str(fixture), 'MENU09_HIVE_DIR': str(root), 'FLUTTER_SUPPRESS_ANALYTICS': 'true'}
server = None
command = [str(args.flutter.resolve()), 'test', '--no-pub', '--reporter', 'expanded', 'test/live/menu09_client_gate_test.dart']

def start(label):
    s = subprocess.Popen(['node', '-r', 'ts-node/register/transpile-only', 'test/menu09-server.ts'], cwd=backend, env=env, stdout=(p / (label + '.log')).open('w'), stderr=subprocess.STDOUT)
    end = time.monotonic() + 40
    while time.monotonic() < end:
        if s.poll() is not None:
            raise RuntimeError('Native bridge failed: ' + label)
        if fixture.exists() and json.loads(fixture.read_text())['backendPid'] == s.pid:
            return s
        time.sleep(.05)
    s.terminate(); s.wait(timeout=10)
    raise TimeoutError(label)

try:
    server = start('native-backend-before')
    before_pid = server.pid
    pg = '/opt/homebrew/opt/postgresql@17/bin/'
    durable_query = 'SELECT jsonb_build_object(\'cutovers\',(SELECT COALESCE(jsonb_agg(jsonb_build_object(\'id\',id,\'authority\',"menuAuthority",\'cutover\',"menuCutover") ORDER BY id),\'[]\') FROM pos."Venue" WHERE "menuCutover" IS NOT NULL),\'reports\',(SELECT COALESCE(jsonb_agg(jsonb_build_object(\'id\',id,\'report\',"menuClientReport",\'observedAt\',"menuClientObservedAt") ORDER BY id),\'[]\') FROM pos."Device" WHERE "menuClientReport" IS NOT NULL))'
    def durable():
        return json.loads(subprocess.check_output([pg+'psql','-h','127.0.0.1','-p',str(e['port']),'-U',e['user'],'-d',u.path[1:],'-X','-Atc',durable_query],text=True))
    with (p / 'native-writer.log').open('w') as log:
        r = subprocess.run(command, cwd=operations, env={**env, 'MENU09_POS_STAGE': 'writer'}, stdout=log, stderr=subprocess.STDOUT, timeout=150)
        assert r.returncode == 0, 'Read native-writer.log'
    writer = json.loads((root / 'writer.json').read_text())
    durable_before = durable()
    server.terminate(); server.wait(timeout=10)
    pg = '/opt/homebrew/opt/postgresql@17/bin/'
    r = subprocess.run([pg + 'pg_ctl', '-D', e['cluster'], '-w', '-l', str(p / 'postgres.log'), 'restart'], capture_output=True, text=True)
    (p / 'postgres-restart.log').write_text(r.stdout + r.stderr)
    assert r.returncode == 0
    server = start('native-backend-after')
    assert server.pid != before_pid
    durable_after = durable()
    assert durable_before == durable_after
    with (p / 'native-reader.log').open('w') as log:
        r = subprocess.run(command, cwd=operations, env={**env, 'MENU09_POS_STAGE': 'reader'}, stdout=log, stderr=subprocess.STDOUT, timeout=150)
        assert r.returncode == 0, 'Read native-reader.log'
    reader = json.loads((root / 'reader.json').read_text())
    assert writer['pid'] != reader['pid'] and writer['saleHash'] == reader['saleHash']
    # Restart proof includes an actual cutover already persisted by HTTP matrix.
    query = 'SELECT COUNT(*) FROM pos."Venue" WHERE "menuCutover" IS NOT NULL AND "menuAuthority"=\'CLOUD\''
    count = int(subprocess.check_output([pg + 'psql', '-h', '127.0.0.1', '-p', str(e['port']), '-U', e['user'], '-d', u.path[1:], '-X', '-Atc', query], text=True))
    assert count > 0
    result = {'status': 'PASS', 'writer': writer, 'reader': reader, 'nativeCommand': command, 'restart': {'backendBefore': before_pid, 'backendAfter': server.pid, 'databaseRestarted': True, 'durableCutoversAfterRestart': count, 'reportsAndCutoversIdentical': durable_before == durable_after, 'durableState': durable_after}, 'temporaryHiveRemoved': True, 'credentialsRemoved': True}
    (p / 'native.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({'status': 'PASS', 'nativePids': [writer['pid'], reader['pid']], 'backendPids': [before_pid, server.pid]}))
finally:
    if server and server.poll() is None:
        server.terminate(); server.wait(timeout=10)
    shutil.rmtree(root)
    if fixture.exists(): fixture.unlink()
