#!/usr/bin/env bash
# Fast-motion review deliverables, from the 4K supersampled render (style-refine/renders/fast-master_2160p30.mp4):
#   vynic-launch-fast-motion-review_1080p30.mp4  (music + SFX, about −16 LUFS)
#   vynic-launch-fast-motion-v2-contact-sheet.jpg   (30 labelled frames)
#   vynic-launch-old-vs-new-v2.jpg                  (same story beats, current film above, fast refine below)
# FFmpeg from the HyperFrames render image (no host FFmpeg needed).
set -euo pipefail
IMG="${HF_IMG:-hyperframes-renderer:0.8.96-arm64}"
film="$(cd "$(dirname "$0")/../.." && pwd)"
ff() { docker run --rm -v "$film:/p" -w /p --entrypoint ffmpeg "$IMG" -hide_banner -loglevel error -y "$@"; }
SRC=style-refine/renders/fast-master_2160p30.mp4
OUT=renders/style-refine/vynic-launch-fast-motion-review-v2_1080p30.mp4
OLD=renders/vynic-launch-master_1080p30.mp4
test -f "$film/$SRC" || { echo "render first: npm run render"; exit 1; }
ff -i "$SRC" -vf "scale=1920:1080:flags=lanczos+accurate_rnd+full_chroma_int" -c:v libx264 -preset slow -tune animation -crf 16 -pix_fmt yuv420p -profile:v high -g 60 \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ar 48000 -c:a aac -b:a 256k -movflags +faststart "$OUT"
sheet() { # $1 = video, $2 = "label time …", $3 = tile, $4 = output
  docker run --rm --entrypoint sh -v "$film:/p" -w /p "$IMG" -c "
set -e; d=renders/style-refine/.sheet; rm -rf \$d; mkdir -p \$d; : > \$d/list.txt; set -- $2; i=0
while [ \$# -gt 0 ]; do lb=\$1; t=\$2; shift 2; i=\$((i+1)); n=\$(printf %02d \$i)
  ffmpeg -hide_banner -loglevel error -y -ss \$t -i $1 -frames:v 1 -vf \"scale=480:-1,drawbox=x=0:y=0:w=150:h=28:color=black@0.65:t=fill,drawtext=fontfile=assets/fonts/Geist-SemiBold.ttf:text='\$lb · \${t}s':x=9:y=7:fontsize=14:fontcolor=white\" \$d/\$n.png
  echo \"file '\$n.png'\" >> \$d/list.txt; done
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i \$d/list.txt -vf 'tile=$3:padding=6:color=0x3a3533' -frames:v 1 -q:v 3 $4
rm -rf \$d"
}
sheet "$OUT" "OPEN 0.7 OPEN 1.3 OPEN 2.2 POS 2.8 POS 3.25 POS 4.05 POS 4.95 POS 5.6 POS 6.2 WIPE 7.2 DATA 8.0 DATA 9.3 WHIP 10.4 MGR 11.3 MGR 12.6 MGR 14.5 MGR 15.3 MGR 16.3 MGR 18.1 MGR 19.0 SCALE 19.45 WEB 20.3 WEB 21.3 WEB 22.6 SPLIT 23.6 CUSTOM 24.7 CUSTOM 26.4 ECO 28.0 LOCK 29.5 LOCK 30.9" 5x6 renders/style-refine/vynic-launch-fast-motion-v2-contact-sheet.jpg
if [ -f "$film/$OLD" ]; then
  sheet "$OLD" "OLD-OPEN 3.4 OLD-POS 9.9 OLD-DATA 20.6 OLD-MGR 26.0 OLD-INV 32.4 OLD-SAAS 42.4 OLD-CUSTOM 50.2 OLD-ECO 54.6" 8x1 renders/style-refine/.old-row.jpg
  sheet "$OUT" "NEW-OPEN 1.3 NEW-POS 4.05 NEW-DATA 9.3 NEW-MGR 12.6 NEW-INV 16.3 NEW-SAAS 22.6 NEW-CUSTOM 23.6 NEW-ECO 28.0" 8x1 renders/style-refine/.new-row.jpg
  ff -i renders/style-refine/.old-row.jpg -i renders/style-refine/.new-row.jpg -filter_complex "[0][1]vstack=inputs=2" -q:v 3 renders/style-refine/vynic-launch-old-vs-new-v2.jpg
  rm -f "$film/renders/style-refine/.old-row.jpg" "$film/renders/style-refine/.new-row.jpg"
fi
echo "done: renders/style-refine/"
