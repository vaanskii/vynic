#!/usr/bin/env bash
# Website deliverables carry no audio track. HyperFrames discovers <audio> at
# compile time, so the score is removed after rendering: a lossless remux
# (-c:v copy -an) with the FFmpeg inside the HyperFrames render image.
set -euo pipefail
IMG="${HF_IMG:-hyperframes-renderer:0.8.96-arm64}"
dir="$(cd "$(dirname "$0")/.." && pwd)/renders"
for f in "$@"; do
  tmp="${f%.*}.tmp.${f##*.}"
  docker run --rm --entrypoint ffmpeg -v "$dir:/r" "$IMG" -hide_banner -loglevel error -y \
    -i "/r/$f" -map 0:v:0 -c:v copy -an -movflags +faststart "/r/$tmp" 2>/dev/null \
    || docker run --rm --entrypoint ffmpeg -v "$dir:/r" "$IMG" -hide_banner -loglevel error -y \
         -i "/r/$f" -map 0:v:0 -c:v copy -an "/r/$tmp"
  mv "$dir/$tmp" "$dir/$f"
  echo "stripped audio: renders/$f"
done
