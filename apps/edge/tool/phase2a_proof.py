"""Real Go + independent Dart processes + Hive A/Hive B convergence proof.
Called inside the disposable Nest/PostgreSQL Phase 1 provisioning harness.
"""
import concurrent.futures
import json
import os
import pathlib
import sqlite3
import subprocess
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[3]


def prove(work, cli, start, stop, venue, installation):
    checks = []
    def passed(name):
        checks.append(name)
        print('PASS Phase 2A: ' + name, flush=True)

    tickets = {name: json.loads(cli('ticket'))['ticket'] for name in ('HiveA', 'HiveB', 'Shadow')}
    edge, info = start()
    address = info['listen']
    dart = os.environ.get('DART', '/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart')

    def client(name, action='catchup', changes=None, expected_exit=0, **extra):
        config = dict(data=str(work / name), address=address,
                      cert=str(work / 'edge/edge-cert.pem'), venue=venue,
                      installation=installation, name=name, ticket=tickets[name],
                      action=action, changes=changes or [], **extra)
        path = work / (name + '-' + str(uuid.uuid4()) + '.json')
        path.write_text(json.dumps(config))
        p = subprocess.run([dart, 'run', 'tool/edge_phase2a_terminal.dart', str(path)],
                           cwd=ROOT / 'apps/operations', capture_output=True, text=True, timeout=35)
        if p.returncode != expected_exit:
            raise RuntimeError(f'{name}/{action} exited {p.returncode}: {p.stderr}\n{p.stdout}')
        if expected_exit:
            return None
        return json.loads(p.stdout.splitlines()[-1])

    def order(oid, line, tables, quantity=1):
        return dict(orderUuid=oid, orderId=1, floor='first', tableIds=tables,
                    items=[dict(lineUuid=line, itemKey='Tea', itemName='Tea',
                                unitPrice=4.0, quantity=quantity, total=4.0*quantity, comment=None)],
                    status='pending', totalAmount=4.0*quantity, includeServiceFee=False,
                    createdAt='2026-09-20T12:00:00.000', createdBy='simulation')

    def change(kind, entity, revision, document=None, tombstone=False):
        return dict(kind=kind, id=entity, expected=revision, document=document, tombstone=tombstone)

    def table(tid, number, oid=None):
        return dict(tableId=tid, floor='first', tableNumber=number, activeOrderUuid=oid)

    def normalize(state):
        return sorted(state['projection'], key=lambda e: (e['kind'], e['id']))

    def convergence():
        a, b = client('HiveA'), client('HiveB')
        assert a['terminalId'] != b['terminalId']
        assert a['data'] != b['data']
        assert normalize(a) == normalize(b)
        assert sorted(a['orders'], key=lambda o: o['id']) == sorted(b['orders'], key=lambda o: o['id'])
        assert sorted(a['tables'], key=lambda o: o['id']) == sorted(b['tables'], key=lambda o: o['id'])
        return a, b

    try:
        soid, sline = str(uuid.uuid4()), str(uuid.uuid4())
        for revision in range(2):
            state = client('Shadow', 'shadow', [change('order', soid, revision, order(soid, sline, [], revision+1))])
            assert json.loads(state['diagnostics'][-1])['kind'] == 'matched'
        passed('Shadow proposals match actual Flutter Order calculation and Hive writes before any isolated coordination test')
        state = client('Shadow', 'shadow', [change('order', soid, 2, order(soid, sline, [], 3))], mismatch=True)
        assert json.loads(state['diagnostics'][-1])['kind'] == 'mismatch'
        passed('Injected operational divergence is durably diagnosed as mismatch')
        a, b = convergence()
        passed('Distinct authenticated terminal identities and separate typed Hive stores')
        oid, line, t1, t2 = [str(uuid.uuid4()) for _ in range(4)]
        seed = [change('order', oid, 0, order(oid, line, [t1])),
                change('table', t1, 0, table(t1, '1', oid)),
                change('table', t2, 0, table(t2, '2'))]
        created = client('HiveA', 'commit', seed)
        assert created['outcome'] == 'COMMITTED'
        convergence()
        passed('Order + occupied Table + free Table committed atomically, then reconciled into Hive A and B')
        edit = change('order', oid, 1, order(oid, line, [t1], 2))
        client('HiveA', 'commit', [edit])
        a, b = convergence()
        passed('Missed event replay converges restarted Terminal B')
        edits = [change('order', oid, 2, order(oid, line, [t1], q)) for q in (3, 4)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(client, name, 'commit', [edit]) for name, edit in zip(('HiveA', 'HiveB'), edits)]
            results = [f.result() for f in futures]
        assert sorted(r['outcome'] for r in results) == ['COMMITTED', 'CONFLICT']
        conflict = next(r for r in results if r['outcome'] == 'CONFLICT')
        assert conflict['current'][0]['revision'] == 3
        passed('Concurrent same-revision edits produce exactly one winner and current-state conflict')
        stale = client('HiveB', 'commit', [change('table', t1, 0, table(t1, '1'))])
        assert stale['outcome'] == 'CONFLICT' and stale['current'][0]['revision'] == 1
        passed('Stale Table occupancy rejected without last-write-wins')
        moved = client('HiveA', 'commit', [change('order', oid, 3, order(oid, line, [t2], 5)),
            change('table', t1, 1, table(t1, '1')), change('table', t2, 1, table(t2, '2', oid))])
        assert moved['outcome'] == 'COMMITTED'
        convergence()
        passed('Transfer-like Order + source Table + destination Table changes share one atomic event')
        before = moved['cursor']
        lost = [change('order', oid, 4, order(oid, line, [t2], 6))]
        client('HiveA', 'commit', lost, expected_exit=17, loseAck=True)
        # Kill Go too, while the acknowledged SQLite WAL is still live.
        stop(edge, kill=True)
        edge, info = start()
        address = info['listen']
        a, b = convergence()
        assert a['cursor'] == before + 1 and a['pending'] is None
        passed('Lost ACK + terminal process death + Edge crash: same durable request recovered exactly once')
        snap = client('HiveB', 'snapshot')
        assert normalize(snap) == normalize(a)
        passed('Atomic Edge snapshot state/cursor agrees with replay projection')
        deleted = client('HiveA', 'commit', [change('order', oid, 5, tombstone=True),
            change('table', t2, 2, table(t2, '2'))])
        assert deleted['outcome'] == 'COMMITTED'
        a, b = convergence()
        assert not any(o['id'] == oid for o in b['orders'])
        assert any(e['id'] == oid and e['tombstone'] for e in b['projection'])
        revive = client('HiveB', 'commit', [change('order', oid, 6, order(oid, line, []))])
        assert revive['outcome'] == 'CONFLICT' and revive['current'][0]['tombstone']
        passed('Deleted/cancelled projection tombstone replays, releases occupancy and refuses resurrection')
        stop(edge)
        edge, info = start()
        address = info['listen']
        a, b = convergence()
        passed('Clean Edge shutdown/startup and terminal restart retain identity, revisions and convergence')
        stop(edge)
        with sqlite3.connect(work / 'edge/edge.db') as db:
            head = db.execute('SELECT sequence FROM coordination').fetchone()[0]
            count = db.execute('SELECT count(*) FROM committed_event').fetchone()[0]
            assert head == count == a['cursor']
            assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        passed('SQLite event count equals Venue sequence; integrity check passes')
        return dict(result='PASS', checks=checks, terminalA=a['terminalId'], terminalB=b['terminalId'],
                    hiveA=str(work/'HiveA'), hiveB=str(work/'HiveB'), sequence=a['cursor'],
                    productionAuthority='PHASE0_PRIMARY_POS', edgeMode='SHADOW',
                    productionCutoverEnabled=False)
    finally:
        stop(edge)
