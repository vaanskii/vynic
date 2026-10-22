#!/usr/bin/env python3
"""SIGKILL/restart three durable checkpoints for each guarded Manager operation; owned synthetic data only."""
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


def require_descendant(native_pid, runner_pid):
    current = native_pid
    for _ in range(20):
        if current == runner_pid:
            return
        value = subprocess.check_output(['ps', '-o', 'ppid=', '-p', str(current)], text=True).strip()
        if not value or int(value) <= 1:
            break
        current = int(value)
    raise RuntimeError('Refusing to signal a process not created by this proof')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--checkpoint', type=int, help='Optional one boundary for debugging')
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix='vynic_mgr03_process_', dir=None))
    command = [str(args.flutter.resolve()), '--suppress-analytics', 'test', '--no-pub', '--reporter', 'expanded', 'test/live/mgr03_process_recovery_test.dart']
    source_files = sorted((project / 'lib').rglob('*.dart')) + [project / 'test/unit/mgr03_edge_operation_test.dart', project / 'test/support/pos03_fixture.dart', project / 'test/support/menu01_fixture.dart', project / 'test/flutter_test_config.dart', project / 'test/live/mgr03_process_recovery_test.dart', Path(__file__).resolve()]
    source_hashes = {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_files}
    base_env = dict(os.environ, FLUTTER_SUPPRESS_ANALYTICS='true')
    proofs = []
    active = None
    def run(stage, path, case):
        log_path = output.with_suffix(f'.{case}-{stage}.log')
        env = dict(base_env, MGR03_PROCESS_DIRECTORY=str(path), MGR03_PROCESS_STAGE=stage, MGR03_PROCESS_KIND=case.rsplit('-boundaries',1)[0] if case.endswith('-boundaries') else case.rsplit('-',1)[0])
        with log_path.open('w') as log:
            result = subprocess.run(command, cwd=project, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, timeout=60)
        if result.returncode:
            raise RuntimeError(f'{case} {stage} failed; inspect {log_path}')
        return hashlib.sha256(log_path.read_bytes()).hexdigest()
    try:
        capture_hashes = {}
        available = 0
        for scenario in ['order_cancel','takeaway_cancel','takeaway_create','dine_in_create','reservation_create','reservation_status','reservation_delete']:
            capture = root / f'{scenario}-capture'; capture.mkdir()
            capture_hash = run('boundaries', capture, f'{scenario}-boundaries')
            trace = json.loads((capture / 'boundaries.json').read_text())['trace']
            intent = trace.index('edge.flush:after') + 1
            effect_prefix = 'reservations.flush:after' if scenario.startswith('reservation_') else 'orders.flush:after'
            effect = trace.index(effect_prefix) + 1
            terminal = trace.index('edge.put:succeeded:before') + 1
            targets = [args.checkpoint] if args.checkpoint else sorted({intent,effect,terminal})
            for target in targets:
                case = f'{scenario}-{target:03d}'
                path = root / case; path.mkdir()
                log_path = output.with_suffix(f'.{case}-writer.log')
                env = dict(base_env, MGR03_PROCESS_DIRECTORY=str(path), MGR03_PROCESS_STAGE='writer', MGR03_PROCESS_KIND=scenario, MGR03_CHECKPOINT=str(target))
                with log_path.open('w') as log:
                    active = subprocess.Popen(command, cwd=project, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
                    deadline = time.monotonic() + 60
                    ready_path = path / 'ready.json'
                    while not ready_path.exists():
                        if active.poll() is not None:
                            raise RuntimeError(f'{case} writer exited before signal; inspect {log_path}')
                        if time.monotonic() >= deadline:
                            raise TimeoutError(f'{case} writer did not reach its boundary')
                        time.sleep(0.02)
                    ready = json.loads(ready_path.read_text())
                    if ready['point'] != trace[target - 1] or not ready['httpBlocked'] or ready['boxesClosed']:
                        raise RuntimeError(f'{case} boundary mismatch')
                    native_pid = int(ready['pid'])
                    require_descendant(native_pid, active.pid)
                    os.kill(native_pid, signal.SIGKILL)
                    writer_exit = active.wait(timeout=30)
                    if writer_exit == 0:
                        raise RuntimeError('Killed writer falsely reported success')
                    active = None
                reader_hash = run('reader', path, case)
                result = json.loads((path / 'result.json').read_text())
                if result['readerPid'] == native_pid or result['status'] != 'PASS':
                    raise RuntimeError('Restart verification did not use a different native process')
                proofs.append({'checkpoint': target, 'point': trace[target - 1], 'signal': 'SIGKILL',
                    'writerExit': writer_exit, 'beforeKill': ready, 'restart': result,
                    'writerLogSha256': hashlib.sha256(log_path.read_bytes()).hexdigest(), 'readerLogSha256': reader_hash})
                output.write_text(json.dumps({'status': 'IN_PROGRESS', 'completed': proofs, 'total': len(targets)}, indent=2) + '\n')
                print(f'{case}/{len(trace)} PASS {trace[target - 1]}', flush=True)
            capture_hashes[scenario] = capture_hash
            available += len(trace)
        if source_hashes != {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_files}:
            raise RuntimeError('Source changed during native proof; repeat on final source')
        result = {'status': 'PASS', 'platform': platform.platform(), 'command': command, 'sourceSha256': source_hashes,
            'checkpointCount': len(proofs), 'availableCheckpointCount': available,
            'checkpointSelection':'each operation: durable Edge intent, native effect flush, before terminal Edge journal write', 'allRealHttpBlocked': True, 'syntheticOnly': True, 'temporaryDirectoryRemoved': True,
            'captureLogSha256': capture_hashes, 'checkpoints': proofs}
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(f'PASS {len(proofs)} SIGKILL/different-process restart checkpoints', flush=True)
    finally:
        if active is not None and active.poll() is None:
            # Only our runner; never find/kill an unrelated application.
            active.terminate(); active.wait(timeout=10)
        shutil.rmtree(root)


if __name__ == '__main__':
    main()
