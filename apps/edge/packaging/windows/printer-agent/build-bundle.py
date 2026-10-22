#!/usr/bin/env python3
"""Validate/package prebuilt pinned artifacts; never install or issue credentials."""
import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    edge = Path(__file__).resolve().parents[3]
    command = ["go", "run", "-mod=readonly", "./cmd/printer-agent", "bundle",
               "--config", str(args.config.resolve(strict=True)),
               "--out", str(args.out.parent.resolve(strict=True) / args.out.name)]
    subprocess.run(command, cwd=edge, check=True)


if __name__ == "__main__":
    main()
