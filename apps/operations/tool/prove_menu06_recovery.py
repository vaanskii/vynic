#!/usr/bin/env python3
"""Native MENU06 proof, with an externally owned disposable PG cluster manifest."""
import argparse, json, os, subprocess, time, signal, tempfile, shutil, urllib.request, re
from urllib.parse import urlparse
from pathlib import Path
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--environment', required=True, type=Path)
parser.add_argument('--flutter', required=True, type=Path)
args = parser.parse_args()
E = json.loads(args.environment.read_text())
P = Path(E['proofDir'])
O = Path(__file__).resolve().parents[1]
B = O.parent / 'backend'
fixture = P / ('native-fixture-' + str(os.getpid()) + '.json')
root = Path(tempfile.mkdtemp(prefix='vynic_menu06_process_', dir='/private/tmp'))
env = {**os.environ, 'MENU06_TEST_DATABASE_URL': E['freshUrl'], 'MENU06_HTTP_FIXTURE': str(fixture), 'MENU06_HIVE_DIR': str(root), 'FLUTTER_SUPPRESS_ANALYTICS': 'true'}
server = None
writer = None
u = urlparse(E['freshUrl'])
assert u.hostname == '127.0.0.1' and re.fullmatch('/disposable_menu06_[a-z0-9_]+', u.path) and ('vankisi' not in u.path)
assert str(P).startswith('/private/tmp/vynic-menu06-proof-') and E['cluster'].startswith('/private/tmp/vynic-menu06-pg-')
assert any((o['name'] == u.path[1:] and o['verificationOwned'] and o['absentBefore'] for o in json.loads((P / 'ownership.json').read_text())))
assert not fixture.exists()
servercmd = ['node', '-r', 'ts-node/register/transpile-only', 'test/menu06-server.ts']
flutter = [str(args.flutter.resolve()), 'test', '--no-pub', '--reporter', 'expanded', 'test/live/menu06_offline_sale_test.dart']

def waitfile(path, process, timeout=120):
    end = time.monotonic() + timeout
    while not path.exists():
        if process.poll() is not None:
            raise RuntimeError('Process exited before ' + str(path))
        if time.monotonic() > end:
            raise TimeoutError(str(path))
        time.sleep(0.05)

def startserver(label, priorPid=None):
    log = (P / (label + '.log')).open('w')
    s = subprocess.Popen(servercmd, cwd=B, env=env, stdout=log, stderr=subprocess.STDOUT)
    end = time.monotonic() + 30
    while True:
        if s.poll() is not None:
            raise RuntimeError('bridge exited ' + label)
        if fixture.exists():
            f = json.loads(fixture.read_text())
            if f['backendPid'] == s.pid:
                return (s, f)
        if time.monotonic() > end:
            raise TimeoutError(label)
        time.sleep(0.05)

def post(f, body):
    v = f['venues'][0]
    r = urllib.request.urlopen(urllib.request.Request(f['baseUrl'] + '/edge/menu/mutations', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'X-POS-Sync-Key': v['credential']}))
    return json.load(r)

def effect(f, body):
    r = urllib.request.urlopen(urllib.request.Request(f['baseUrl'] + '/edge/inventory/consumption', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'X-POS-Sync-Key': f['venues'][0]['credential']}))
    return json.load(r)
try:
    (server, f) = startserver('native-server')
    flutter.insert(2, '--dart-define=VYNIC_API_URL=' + f['baseUrl'])
    with (P / 'native-writer.log').open('w') as log:
        writer = subprocess.Popen(flutter, cwd=O, env={**env, 'MENU06_POS_STAGE': 'writer'}, stdout=log, stderr=subprocess.STDOUT)
        waitfile(root / 'writer.json', writer)
        w = json.loads((root / 'writer.json').read_text())
        nativePid = int(w['pid'])
        ancestor = nativePid
        for i in range(20):
            if ancestor == writer.pid:
                break
            ancestor = int(subprocess.check_output(['ps', '-o', 'ppid=', '-p', str(ancestor)], text=True).strip())
            assert ancestor > 1
        else:
            raise RuntimeError('Not owned native PID')
        import uuid
        removal = {'mutationId': str(uuid.uuid4()), 'entityType': 'ITEM', 'entityId': f['product']['itemId'], 'operation': 'DELETE', 'expectedRevision': 1}
        accepted = post(f, removal)
        os.kill(nativePid, signal.SIGKILL)
        exitcode = writer.wait(timeout=30)
        assert exitcode != 0
    with (P / 'native-reader.log').open('w') as log:
        r = subprocess.run(flutter, cwd=O, env={**env, 'MENU06_POS_STAGE': 'reader'}, stdout=log, stderr=subprocess.STDOUT, timeout=120)
        assert r.returncode == 0, 'Read native-reader.log'
    reader = json.loads((root / 'reader.json').read_text())
    assert w['pid'] != reader['pid'] and w['saleSha256'] == reader['saleSha256']
    sale = reader['sale']
    body = {'posSaleId': sale['posSaleId'], 'closureId': sale['closureId'], 'orderId': sale['orderId'], 'businessDate': sale['date'], 'closedAt': sale['closedAt'], 'snapshot': sale['inventoryConsumption']}
    beforeRestart = effect(f, body)
    oldBackend = f['backendPid']
    server.terminate()
    server.wait(timeout=10)
    pg = subprocess.run(['pg_ctl', '-D', E['cluster'], '-w', '-l', str(P / 'postgres.log'), 'restart'], capture_output=True, text=True)
    (P / 'postgres-restart.log').write_text(pg.stdout + pg.stderr)
    assert pg.returncode == 0
    (server, f) = startserver('native-server-restarted', oldBackend)
    assert f['backendPid'] != oldBackend
    assert post(f, removal) == {**accepted, 'duplicate': True}
    afterRestart = effect(f, body)
    assert afterRestart == beforeRestart
    reverse = {**body, 'reversedAt': '2026-10-01T11:00:00.000Z', 'restoreBusinessDate': '2026-10-01'}
    reversal = effect(f, reverse)
    assert effect(f, reverse) == reversal
    q = 'SELECT json_build_object(\'movements\',json_agg("quantityDeltaBase"::text ORDER BY "createdAt"),\'sum\',SUM("quantityDeltaBase")::text) FROM pos."StockMovement" WHERE "stockItemId"=\'' + f['product']['stockId'] + "'"
    conservation = json.loads(subprocess.check_output(['psql', '-h', '127.0.0.1', '-p', str(E['port']), '-U', E['user'], '-d', E['freshUrl'].split('/')[-1], '-X', '-At', '-c', q], text=True))
    assert conservation['movements'] == ['10.000000', '-2.000000', '2.000000'] and conservation['sum'] == '10.000000'
    result = {'status': 'PASS', 'writer': w, 'reader': reader, 'killedOwnedNativePid': nativePid, 'expectedWriterExit': exitcode, 'restart': {'backendBefore': oldBackend, 'backendAfter': f['backendPid'], 'databaseRestarted': True, 'exactRetirementReplay': True, 'consumptionReplay': afterRestart}, 'reversal': reversal, 'conservation': conservation, 'nativeCommand': flutter, 'temporaryHiveRemoved': True}
    (P / 'native.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'nativePids': [w['pid'], reader['pid']], 'conservation': conservation}))
finally:
    if server and server.poll() is None:
        server.terminate()
        server.wait(timeout=10)
    if writer and writer.poll() is None:
        writer.terminate()
        writer.wait(timeout=10)
    shutil.rmtree(root)
    if fixture.exists():
        fixture.unlink()
