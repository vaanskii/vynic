#!/usr/bin/env python3
"""Real subprocess/TLS/SQLite/Nest proof. Only disposable loopback phase1_ DBs."""
import argparse
import json
import os
import pathlib
import select
import shutil
import sqlite3
import subprocess
import tempfile
import time
import urllib.request
import urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[3]
EDGE = ROOT / "apps/edge"


def run(args, **kwargs):
    p = subprocess.run(
        [str(x) for x in args], text=True, capture_output=True, timeout=45, **kwargs
    )
    if p.returncode:
        raise RuntimeError(f"{args[0]} failed: {p.stderr}")
    return p.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--database-url", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--phase2a", action="store_true")
    opts = parser.parse_args()
    from urllib.parse import urlparse

    u = urlparse(opts.database_url)
    if (
        u.hostname not in ("127.0.0.1", "localhost")
        or not u.path.startswith("/phase1_")
        or "vankisi" in opts.database_url
    ):
        raise RuntimeError("Disposable phase1_ database required")
    os.umask(0o077)
    work = pathlib.Path(tempfile.mkdtemp(prefix="vynic-edge-proof-"))
    processes = []
    edge = None
    checks = []
    report = {"checks": checks, "workspace": str(work)}

    def check(name):
        checks.append(name)
        print("PASS " + name, flush=True)

    def stop(p, kill=False):
        if p and p.poll() is None:
            p.kill() if kill else p.terminate()
            p.wait(timeout=10)
            if not kill and p.returncode != 0:
                raise RuntimeError("Unclean shutdown")

    try:
        env = dict(
            os.environ,
            TENANT_INTEGRATION_DATABASE_URL=opts.database_url,
            EDGE_DEV_INFO_FILE=str(work / "cloud.json"),
        )
        log = open(work / "nest.log", "w")
        backend = subprocess.Popen(
            [
                str(ROOT / "apps/backend/node_modules/.bin/ts-node"),
                "-T",
                "scripts/edge-foundation-dev.ts",
            ],
            cwd=ROOT / "apps/backend",
            env=env,
            stdout=log,
            stderr=log,
        )
        processes.append(backend)
        deadline = time.monotonic() + 30
        while not (work / "cloud.json").exists():
            if backend.poll() is not None:
                raise RuntimeError((work / "nest.log").read_text())
            if time.monotonic() > deadline:
                raise RuntimeError("Nest startup timeout")
            time.sleep(0.1)
        cloud = json.loads((work / "cloud.json").read_text())
        (work / "cloud-key.pem").write_text(cloud["publicKey"])

        def post(path, body, expected=201):
            req = urllib.request.Request(
                cloud["url"] + path,
                data=json.dumps(body).encode(),
                headers={
                    "Authorization": "Bearer " + cloud["token"],
                    "Content-Type": "application/json",
                },
            )
            try:
                with urllib.request.urlopen(req, timeout=10) as r:
                    code, data = r.status, r.read()
            except urllib.error.HTTPError as e:
                code, data = e.code, e.read()
            if code != expected:
                raise RuntimeError(f"Cloud HTTP {code}: {data.decode()}")
            return json.loads(data)

        def cli(action, *args, data=None):
            return run(
                [EDGE / "bin/edge", action, "--data", data or work / "edge", *args]
            )

        identity = json.loads(cli("init"))
        installation = identity["installationId"]
        venue = cloud["venueId"]
        base = f"/platform/venues/{venue}/edge-foundations"
        grant = post(base, identity)
        (work / "grant.txt").write_text(grant["grant"])
        cli(
            "bind",
            "--grant-file",
            work / "grant.txt",
            "--cloud-key",
            work / "cloud-key.pem",
        )
        check("Nest Platform authentication + Cloud-signed Venue/installation binding")
        for terminal in ("A", "B", "Dart"):
            (work / (terminal + "-ticket.json")).write_text(cli("ticket"))

        def start():
            p = subprocess.Popen(
                [
                    str(EDGE / "bin/edge"),
                    "serve",
                    "--data",
                    str(work / "edge"),
                    "--listen",
                    "127.0.0.1:0",
                ],
                stdout=subprocess.PIPE,
                stderr=open(work / "edge.log", "a"),
                text=True,
            )
            processes.append(p)
            if not select.select([p.stdout], [], [], 10)[0]:
                raise RuntimeError("Edge startup timeout")
            line = p.stdout.readline()
            if not line:
                raise RuntimeError(
                    "Edge startup failed: " + (work / "edge.log").read_text()
                )
            return p, json.loads(line)

        edge, first = start()
        address = first["listen"]

        def sim(name, *extra):
            return [
                EDGE / "bin/terminal-sim",
                "--data",
                work / name,
                "--address",
                address,
                "--cert",
                work / "edge/edge-cert.pem",
                "--venue",
                venue,
                "--installation",
                installation,
                "--name",
                name,
                *extra,
            ]

        clients = [
            subprocess.Popen(
                [
                    str(x)
                    for x in sim(
                        name,
                        "--ticket-file",
                        work / (name + "-ticket.json"),
                        "--watch",
                        "3s",
                    )
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for name in ("A", "B")
        ]
        processes.extend(clients)
        output = []
        for p in clients:
            out, err = p.communicate(timeout=15)
            if p.returncode:
                raise RuntimeError(err)
            output += [json.loads(line) for line in out.splitlines()]
        ids = {x["terminal_id"] for x in output}
        assert len(ids) == 2
        assert any(x.get("connected_streams", 0) == 2 for x in output)
        assert all(
            x["mode"] == "FOUNDATION_ONLY"
            and not x.get("business_mutations_enabled", False)
            for x in output
        )
        report.update(
            installationId=installation, venueId=venue, terminalIds=sorted(ids)
        )
        check(
            "Terminal A and B: distinct persisted identities + concurrent authenticated TLS streams"
        )
        run(sim("A", "--ticket-file", work / "A-ticket.json"))
        check("Exact pairing retry is idempotent")
        run(
            sim(
                "Replay",
                "--ticket-file",
                work / "A-ticket.json",
                "--expect-code",
                "AlreadyExists",
            )
        )
        check("Consumed ticket rejects different terminal replay")
        run(sim("A", "--invalid-credential", "--expect-code", "Unauthenticated"))
        check("Invalid terminal credential rejected")
        run(sim("A", "--venue", cloud["venueB"], "--expect-code", "PermissionDenied"))
        check("Wrong Venue rejected")
        run(sim("A", "--major", "2", "--expect-code", "FailedPrecondition"))
        check("Protocol major mismatch rejected")
        locked = subprocess.run(
            [str(EDGE / "bin/edge"), "serve", "--data", str(work / "edge")],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert locked.returncode != 0 and "already in use" in locked.stderr
        check("Second Edge process cannot open the same store")
        wal = work / "edge/edge.db-wal"
        assert wal.exists() and wal.stat().st_size > 32
        stop(edge, kill=True)
        edge, second = start()
        address = second["listen"]
        assert first["bootId"] != second["bootId"]
        for name in ("A", "B"):
            result = json.loads(
                run(
                    sim(name, "--ticket-file", work / (name + "-ticket.json"))
                ).splitlines()[0]
            )
            assert (
                result["terminal_id"] in ids and result["boot_id"] == second["bootId"]
            )
        check(
            "SIGKILL with populated WAL: stable installation/pairing/session + authenticated reconnect"
        )
        host, port = address.split(":")
        dart = os.environ.get("DART", "dart")
        dartArgs = [
            dart,
            "run",
            "bin/main.dart",
            work / "Dart",
            host,
            port,
            work / "edge/edge-cert.pem",
            venue,
            installation,
            work / "Dart-ticket.json",
        ]
        dartResult = json.loads(
            run(dartArgs, cwd=EDGE / "tool/dart_sim").splitlines()[-1]
        )
        assert dartResult["terminalId"] not in ids
        check(
            "Generated Dart client pairs/handshakes with Go over TLS using its own identity"
        )
        cli("init", data=work / "untrusted-edge")
        wrong = list(dartArgs)
        wrong[-4] = work / "untrusted-edge/edge-cert.pem"
        rejected = subprocess.run(
            [str(x) for x in wrong],
            cwd=EDGE / "tool/dart_sim",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert (
            rejected.returncode != 0 and "CERTIFICATE_VERIFY_FAILED" in rejected.stderr
        )
        check("Dart rejects a different certificate pin; no insecure TLS fallback")
        stop(edge)
        edge, third = start()
        address = third["listen"]
        run(sim("B"))
        stop(edge)
        check("Graceful shutdown/startup and terminal reconnect")
        db = sqlite3.connect(work / "edge/edge.db")
        assert db.execute("select count(*) from terminal").fetchone()[0] == 3
        assert db.execute("select count(*) from session").fetchone()[0] == 3
        db.close()
        check(
            "Three restart-stable terminals/sessions; replay creates no duplicate metadata"
        )
        for kind in ("newer", "corrupt", "checksum"):
            d = work / kind
            d.mkdir()
            shutil.copyfile(work / "edge/edge.db", d / "edge.db")
            if kind == "corrupt":
                (d / "edge.db").write_bytes(b"corrupted database")
            else:
                c = sqlite3.connect(d / "edge.db")
                c.execute(
                    "PRAGMA user_version=999"
                    if kind == "newer"
                    else "UPDATE schema_migration SET checksum='altered'"
                )
                c.commit()
                c.close()
            p = subprocess.run(
                [str(EDGE / "bin/edge"), "serve", "--data", str(d)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert p.returncode != 0 and "local store refused" in p.stderr
        check("Newer schema, corruption and changed migration ledger refuse startup")
        if opts.phase2a:
            from phase2a_proof import prove
            report["phase2a"] = prove(work, cli, start, stop, venue, installation)
        aid = json.loads((work / "A/terminal.json").read_text())["TerminalID"]
        cli("revoke", "--terminal", aid)
        edge, fourth = start()
        address = fourth["listen"]
        run(sim("A", "--expect-code", "Unauthenticated"))
        run(sim("B"))
        stop(edge)
        check("Durable revocation rejects A while B still authenticates")
        post(base + "/" + installation + "/revoke", {})
        post(base, identity, 409)
        check("Cloud registration revocation blocks new bootstrap grants")
        stop(backend)
        report["result"] = "PASS"
        pathlib.Path(opts.output).write_text(json.dumps(report, indent=2) + "\n")
        print("Proof report: " + opts.output)
    finally:
        for p in reversed(processes):
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    p.kill()
                    p.wait()


if __name__ == "__main__":
    main()
