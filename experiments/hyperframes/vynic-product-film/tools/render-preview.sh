#!/usr/bin/env bash
# Review preview: render only the opening of the film (Scene 1 + Scene 2).
# HyperFrames has no frame-range flag, so this renders a temporary copy of
# the composition whose root duration is cut to END seconds. Same HTML, same
# timeline, same Docker renderer as the full film: the frames are identical.
#
#   tools/render-preview.sh          → renders/preview/vynic-opening_0-8.0s_1080p30.mp4
#   tools/render-preview.sh 5.2      → a different end point (Scenes 1–2 end at 8.0)
set -euo pipefail
END="${1:-8.0}"
IMG="${HF_IMG:-hyperframes-renderer:0.8.96-arm64}"
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/renders/.preview-src"
out_dir="$root/renders/preview"
name="vynic-opening_0-${END}s_1080p30.mp4"

rm -rf "$src" && mkdir -p "$src" "$out_dir"
cp -R "$root/index.html" "$root/hyperframes.json" "$root/meta.json" "$root/assets" "$src/"
# Root, stage clip and score all end at END.
sed -i '' -E "s/data-duration=\"22\"/data-duration=\"${END}\"/g" "$src/index.html"

(cd "$src" && npx --yes hyperframes@0.8.96 render --docker --quality delivery --fps 30 --output "renders/raw.mp4" .)

# A 0.3s audio fade so the cut-off score doesn't click (video stream copied untouched).
fade_at="$(awk -v e="$END" 'BEGIN { printf "%.2f", e - 0.3 }')"
docker run --rm --entrypoint ffmpeg -v "$src/renders:/in" -v "$out_dir:/out" "$IMG" -hide_banner -loglevel error -y \
  -i /in/raw.mp4 -c:v copy -af "afade=t=out:st=${fade_at}:d=0.3" -c:a aac -b:a 192k -movflags +faststart "/out/$name"
rm -rf "$src"
echo "preview: renders/preview/$name"
