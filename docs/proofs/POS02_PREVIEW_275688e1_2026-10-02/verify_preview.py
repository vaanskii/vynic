#!/usr/bin/env python3
"""Read-only integrity and saved-evidence checks; never launches POS or printers."""
import hashlib
import json
from pathlib import Path
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def main():
    root = Path(__file__).resolve().parent
    checks = json.loads((root / "CHECKSUMS.json").read_text())
    for name, digest in checks["filesSha256"].items():
        require(sha((root / name).read_bytes()) == digest, f"File mismatch: {name}")
    guide = root.parent.parent / "POS02_PREVIEW.md"
    require(sha(guide.read_bytes()) == checks["guideSha256"], "Guide mismatch")
    foundation = root.parent / "POS02_CHECKPOINT_275688e1_2026-10-02"
    require(sha((foundation / "CHECKSUMS.json").read_bytes()) == checks["foundationChecksumSha256"], "Foundation manifest mismatch")
    base = json.loads((foundation / "candidate-source-sha256.json").read_text())
    sources = json.loads((root / "source-sha256.json").read_text())
    require(len(base) == 867 and len(sources) == 870, "Unexpected source file count")
    require(all(sources.get(name) == digest for name, digest in base.items()), "Sealed candidate changed")
    with zipfile.ZipFile(root / "preview-source.zip") as archive:
        require(archive.testzip() is None, "Source ZIP CRC failure")
        require(set(archive.namelist()) == set(sources) | {"POS02_SOURCE_SHA256.json", "POS02_PROFILE.json"}, "Unexpected source ZIP entries")
        for name, digest in sources.items():
            require(sha(archive.read(name)) == digest, f"Source mismatch: {name}")
        require(json.loads(archive.read("POS02_SOURCE_SHA256.json")) == sources, "Embedded source manifest mismatch")
        profile = json.loads(archive.read("POS02_PROFILE.json"))
        require(profile["printerHost"] == "" and profile["entrypoint"] == "tool/pos02_preview.dart", "Unexpected preview profile")
    with zipfile.ZipFile(root / "mac-preview.zip") as archive:
        require(archive.testzip() is None, "Mac ZIP CRC failure")
        for name, record in json.loads((root / "mac-app-manifest.json").read_text()).items():
            require(sha(archive.read(name)) == record["sha256"], f"Mac app mismatch: {name}")
    with zipfile.ZipFile(root / "logs.zip") as archive:
        require(archive.testzip() is None, "Logs ZIP CRC failure")
        for name, digest in json.loads((root / "log-sha256.json").read_text()).items():
            require(sha(archive.read(name)) == digest, f"Log mismatch: {name}")
        events = [json.loads(line) for line in archive.read("preview-tests.jsonl").decode().splitlines() if line.startswith("{")]
        tests = [event for event in events if event.get("type") == "testDone" and not event.get("hidden")]
        require(len(tests) == 67 and all(event["result"] == "success" and not event["skipped"] for event in tests), "Unexpected saved test results")
        require(any(event.get("type") == "done" and event.get("success") is True for event in events), "Test completion missing")
        require(not any(event.get("type") == "error" for event in events), "Saved tests contain an error")
        require("No issues found!" in archive.read("preview-analyze.log").decode(), "Analyzer success missing")
        require("Built build/macos/Build/Products/Debug/Vynic Manager.app" in archive.read("preview-build.log").decode(), "Mac compile success missing")
    print(json.dumps({"status": "PASS", "sourceFiles": len(sources), "sealedCandidateFilesUnchanged": len(base), "savedPassingChecks": len(tests), "macPreview": "compile-only; GUI not launched", "printerHost": "", "physicalAcceptance": "PENDING", "windowsExecution": "PENDING", "milestoneDone": False}, indent=2))


if __name__ == "__main__":
    main()
