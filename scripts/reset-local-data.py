#!/usr/bin/env python3
"""Reset this macOS development installation; retain accounts and product plans."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
PG = Path('/opt/homebrew/opt/postgresql@17/bin')
DB_ARGS = ['-h', 'localhost', '-p', '5432', '-d', 'vynic']
PRESERVED = ['PlatformUser', 'CustomerAccount', 'Plan', 'PlanFeature',
             'Feature', 'OnboardingPolicy', '_prisma_migrations']


def sql(query):
    return subprocess.check_output(
        [str(PG / 'psql'), *DB_ARGS, '-X', '-v', 'ON_ERROR_STOP=1', '-At', '-c', query],
        text=True).strip()


def identifier(value):
    return '"' + value.replace('"', '""') + '"'


def table_name(schema, table):
    return identifier(schema) + '.' + identifier(table)


def processes():
    rows = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
    return [(int(row.strip().split(None, 1)[0]), row.strip().split(None, 1)[1])
            for row in rows.splitlines() if row.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--yes', action='store_true',
                        help='Back up and erase local restaurant/POS data, including organizations.')
    args = parser.parse_args()
    if not args.yes:
        parser.error('Run with --yes to reset localhost:5432/vynic and local POS data. '
                     'Login accounts, plans and backups are retained.')
    os.umask(0o077)
    backup_root = Path.home() / 'Library/Application Support/Vynic Reset Backups'
    backup_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Prevent two reset commands from moving the same files concurrently.
    with (backup_root / '.reset.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        reset(backup_root)


def reset(backup_root):
    if sql('SELECT current_database()') != 'vynic':
        raise RuntimeError('Unexpected database; reset refused.')
    if sql('SELECT host(inet_server_addr())') not in ('::1', '127.0.0.1'):
        raise RuntimeError('Non-loopback database; reset refused.')
    # Match only this checkout’s compiled backend and desktop apps.
    backend_pattern = re.compile(r'^node --enable-source-maps ' +
                                 re.escape(str(ROOT / 'apps/backend/dist/src/main')) + r'(?:\.js)?$')
    rows = processes()
    backends = [pid for pid, command in rows if backend_pattern.fullmatch(command)]
    listener = subprocess.run(['lsof', '-nP', '-t', '-iTCP:3000', '-sTCP:LISTEN'],
                              capture_output=True, text=True)
    if listener.returncode not in (0, 1):
        raise RuntimeError('Unable to inspect backend listener; reset refused.')
    if any(int(pid) not in backends for pid in listener.stdout.split()):
        raise RuntimeError('Unknown server on port 3000; stop it before resetting.')
    targets = [(path, path.name) for path in sorted(
        (Path.home() / 'Library/Containers/ge.vynic.pos/Data/Documents').glob('Vpos_Data_*_local'))]
    targets += [(Path.home() / 'Library/Containers/ge.vynic.manager/Data/Documents/VynicManager',
                 'manager-cache'), (ROOT / 'apps/backend/.data/website-media', 'website-media')]
    for source, _ in targets:
        if source.is_symlink():
            raise RuntimeError('Refusing symlink data directory: ' + str(source))
    desktop_pids = [pid for pid, command in rows
                    if command.startswith(str(ROOT / 'apps/operations') + '/')
                    and any(command.endswith(f'Vynic {app}.app/Contents/MacOS/Vynic {app}')
                            for app in ('POS', 'Manager'))]
    for pid in desktop_pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 15
    while set(desktop_pids) & {pid for pid, _ in processes()}:
        if time.monotonic() > deadline:
            raise RuntimeError('POS/Manager did not quit. Close the app and retry.')
        time.sleep(0.2)
    suspended = []
    moved = []
    committed = False
    backup = backup_root / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(mode=0o700)
    try:
        for pid in backends:
            os.kill(pid, signal.SIGSTOP)
            suspended.append(pid)
        time.sleep(2)  # Allow already-issued database queries to finish.
        subprocess.run([str(PG / 'pg_dump'), *DB_ARGS, '-Fc', '-f',
                        str(backup / 'website-local.dump')], check=True)
        subprocess.run([str(PG / 'pg_restore'), '--list', str(backup / 'website-local.dump')],
                       check=True, stdout=subprocess.DEVNULL)
        tables = [row.split('|') for row in sql(
            "SELECT schemaname,tablename FROM pg_tables "
            "WHERE schemaname IN ('pos','website') ORDER BY 1,2").splitlines()]
        kept = [(s, t) for s, t in tables if t == '_prisma_migrations'
                or (s == 'pos' and t in PRESERVED)]
        counts = {table_name(s, t): sql('SELECT count(*) FROM ' + table_name(s, t))
                  for s, t in kept}
        cleared = [(s, t) for s, t in tables if (s, t) not in kept
                   and (s, t) != ('pos', 'Organization')]
        if not cleared:
            raise RuntimeError('Expected application tables missing; reset refused.')
        for source, label in targets:
            if source.exists():
                source.rename(backup / label)
                moved.append({'source': str(source), 'backup': str(backup / label)})
                source.mkdir(mode=0o700)
        manifest = {'database': 'localhost:5432/vynic', 'preservedCounts': counts,
                    'clearedTables': cleared, 'movedDirectories': moved}
        (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2))
        sql("BEGIN; SET LOCAL lock_timeout = '10s'; TRUNCATE TABLE " +
            ', '.join(table_name(s, t) for s, t in cleared) +
            ' RESTART IDENTITY; UPDATE pos."CustomerAccount" SET "organizationId" = NULL; '
            'DELETE FROM pos."Organization"; COMMIT;')
        committed = True
        for name, count in counts.items():
            if sql('SELECT count(*) FROM ' + name) != count:
                raise RuntimeError('Preserved row count changed: ' + name)
        for s, t in cleared + [('pos', 'Organization')]:
            if sql('SELECT count(*) FROM ' + table_name(s, t)) != '0':
                raise RuntimeError('Table not empty: ' + table_name(s, t))
        print('Local reset complete. Restaurants, organizations, menus, orders and POS enrollment cleared.')
        print('Login accounts and product plans retained. Reopen POS and refresh the website.')
        print('Backup: ' + str(backup))
    except BaseException:
        if not committed:
            for entry in reversed(moved):
                source = Path(entry['source'])
                if source.exists():
                    source.rmdir()
                Path(entry['backup']).rename(source)
        raise
    finally:
        for pid in suspended:
            os.kill(pid, signal.SIGCONT)


if __name__ == '__main__':
    main()
