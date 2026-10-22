#!/usr/bin/env python3
"""SIGKILL/reopen proof using only self-created synthetic Hive directories."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
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
    directory = Path(tempfile.mkdtemp(prefix='vynic_menu02_process_', dir='/private/tmp'))
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(args.flutter.resolve()), 'test', '--no-pub', '--reporter', 'expanded',
               'test/live/menu02_process_restart_test.dart']
    environment = dict(os.environ, FLUTTER_SUPPRESS_ANALYTICS='true',
                       MENU02_PROCESS_DIRECTORY=str(directory))
    writer_log = output.with_suffix('.writer.log')
    reader_log = output.with_suffix('.reader.log')
    writer = None
    try:
        with writer_log.open('w') as log:
            writer = subprocess.Popen(command, cwd=project, stdout=log, stderr=subprocess.STDOUT,
                                      stdin=subprocess.DEVNULL,
                                      env=dict(environment, MENU02_PROCESS_STAGE='writer'))
            deadline = time.monotonic() + 60
            ready_file = directory / 'ready.json'
            while not ready_file.exists():
                if writer.poll() is not None:
                    raise RuntimeError(f'Writer exited before checkpoint; inspect {writer_log}')
                if time.monotonic() >= deadline:
                    raise TimeoutError('Writer did not signal its checkpoint')
                time.sleep(0.02)  # observes a barrier; never chooses the crash timing
            ready = json.loads(ready_file.read_text())
            native_pid = int(ready['pid'])
            # Only kill a descendant of the Flutter runner this script started.
            ancestor = native_pid
            for _ in range(20):
                if ancestor == writer.pid:
                    break
                ancestor = int(subprocess.check_output(
                    ['ps', '-o', 'ppid=', '-p', str(ancestor)], text=True).strip())
                if ancestor <= 1:
                    raise RuntimeError('Checkpoint PID is not our child')
            else:
                raise RuntimeError('Checkpoint process ancestry is invalid')
            os.kill(native_pid, signal.SIGKILL)
            writer_exit = writer.wait(timeout=30)
            if writer_exit == 0:
                raise RuntimeError('Killed writer unexpectedly reported test success')
        with reader_log.open('w') as log:
            reader = subprocess.run(command, cwd=project, stdout=log, stderr=subprocess.STDOUT,
                                    stdin=subprocess.DEVNULL, timeout=60,
                                    env=dict(environment, MENU02_PROCESS_STAGE='reader'))
        if reader.returncode:
            raise RuntimeError(f'Reader failed; inspect {reader_log}')
        result = json.loads((directory / 'result.json').read_text())
        if result['writerPid'] == result['readerPid']:
            raise RuntimeError('Restart must use another native process')
        result.update({
            'signal': 'SIGKILL', 'checkpoint': ready['checkpoint'],
            'projectionEmptyAtKill': ready['projectionEmptyAtKill'],
            'writerExit': writer_exit, 'readerExit': reader.returncode,
            'platform': platform.platform(), 'command': command,
            'writerLogSha256': hashlib.sha256(writer_log.read_bytes()).hexdigest(),
            'readerLogSha256': hashlib.sha256(reader_log.read_bytes()).hexdigest(),
            'temporaryDirectoryRemoved': True,
        })
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2))
    finally:
        if writer is not None and writer.poll() is None:
            writer.terminate()
            writer.wait(timeout=10)
        shutil.rmtree(directory)  # only the mkdtemp directory created above


if __name__ == '__main__':
    main()
