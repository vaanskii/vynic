#!/bin/sh
# Development only. All credentials/artifacts live outside the repository.
set -eu
exec python3 "$(dirname "$0")/local_windows_release_test.py" "$@"
