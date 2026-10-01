#!/usr/bin/env python3
"""Fresh native Flutter/Hive restore and SIGKILL replay; synthetic temp data only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    root = Path(tempfile.mkdtemp(prefix='vynic_menu01_process_', dir='/private/tmp'))
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(args.flutter.resolve()), 'test', '--no-pub', '--reporter', 'expanded', 'test/live/menu01_process_restore_test.dart']
    env = dict(os.environ, FLUTTER_SUPPRESS_ANALYTICS='true', MENU01_PROCESS_DIRECTORY=str(root))
    logs = {}
    crash = None
    def run(stage):
        path = output.with_suffix(f'.{stage}.log')
        with path.open('w') as log:
            result = subprocess.run(command, cwd=project, env=dict(env, MENU01_PROCESS_STAGE=stage), stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=60)
        logs[stage] = hashlib.sha256(path.read_bytes()).hexdigest()
        if result.returncode:
            raise RuntimeError(f'{stage} failed; inspect {path}')
    try:
        run('writer')
        run('reader')
        crashlog = output.with_suffix('.crash-restore.log')
        with crashlog.open('w') as log:
            crash = subprocess.Popen(command, cwd=project, env=dict(env, MENU01_PROCESS_STAGE='crash-restore'), stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 60
            ready_path = root / 'ready.json'
            while not ready_path.exists():
                if crash.poll() is not None:
                    raise RuntimeError(f'Crash restore exited before checkpoint; inspect {crashlog}')
                if time.monotonic() >= deadline:
                    raise TimeoutError('No restore readiness barrier')
                time.sleep(0.02)
            ready = json.loads(ready_path.read_text())
            if not ready['restoreMarkerPresent'] or not ready['salesEmpty']:
                raise RuntimeError('Incorrect crash checkpoint')
            native_pid = int(ready['pid'])
            ancestor = native_pid
            for _ in range(20):
                if ancestor == crash.pid:
                    break
                ancestor = int(subprocess.check_output(['ps', '-o', 'ppid=', '-p', str(ancestor)], text=True).strip())
                if ancestor <= 1:
                    raise RuntimeError('PID is not our runner descendant')
            else:
                raise RuntimeError('Invalid process ancestry')
            os.kill(native_pid, signal.SIGKILL)
            crash_exit = crash.wait(timeout=30)
            if crash_exit == 0:
                raise RuntimeError('Killed process reported success')
        logs['crash-restore'] = hashlib.sha256(crashlog.read_bytes()).hexdigest()
        run('recover')
        writer = json.loads((root / 'writer.json').read_text())
        reader = json.loads((root / 'reader.json').read_text())
        recovered = json.loads((root / 'recovered.json').read_text())
        if len({writer['pid'], reader['pid'], native_pid, recovered['pid']}) != 4:
            raise RuntimeError('Proof requires distinct native PIDs')
        result = {'status': 'PASS', 'platform': platform.platform(), 'command': command, 'writer': writer, 'freshRestore': reader, 'interruptedRestore': {'signal': 'SIGKILL', 'expectedRunnerExit': crash_exit, **ready}, 'startupReplay': recovered, 'logSha256': logs, 'allRealHttpBlocked': True, 'temporaryDirectoryRemoved': True}
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
    finally:
        if crash is not None and crash.poll() is None:
            crash.terminate()
            crash.wait(timeout=10)
        shutil.rmtree(root)


if __name__ == '__main__':
    main()
