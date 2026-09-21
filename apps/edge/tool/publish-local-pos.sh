#!/bin/sh
# Local development only: build in Parallels, sign/publish on this Mac.
set -eu
exec python3 "$(dirname "$0")/publish_local_pos.py" "$@"
