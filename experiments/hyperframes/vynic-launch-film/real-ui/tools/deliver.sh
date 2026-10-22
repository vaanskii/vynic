#!/usr/bin/env bash
# Fast-motion review deliverables, from the 4K supersampled render (real-ui/renders/real-ui-master_2160p30.mp4):
#   vynic-launch-fast-motion-review_1080p30.mp4  (music + SFX, about −16 LUFS)
#   vynic-launch-real-ui-contact-sheet.jpg   (30 labelled frames)
#   vynic-launch-real-ui-old-vs-new.jpg                  (same story beats, current film above, fast refine below)
# FFmpeg from the HyperFrames render image (no host FFmpeg needed).
set -euo pipefail
IMG="${HF_IMG:-hyperframes-renderer:0.8.96-arm64}"
film="$(cd "$(dirname "$0")/../.." && pwd)"
ff() { docker run --rm -v "$film:/p" -w /p --entrypoint ffmpeg "$IMG" -hide_banner -loglevel error -y "$@"; }
SRC=real-ui/renders/real-ui-master_2160p30.mp4
OUT=renders/style-refine/vynic-launch-real-ui-review_1080p30.mp4
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
sheet "$OUT" "OPEN 1.3 POS 2.9 POS 3.9 POS 4.4 POS 5.8 POS 6.9 POS 7.8 COUNT 8.9 TAKEAWAY 9.9 RESERV 10.9 ADMIN 11.9 ADMIN 12.7 WIPE 13.3 DATA 14.9 WHIP 16.6 MGR 17.95 MGR 19.0 MGR 20.6 INV 21.5 RECV 22.3 RECV 23.3 RECV 24.8 STOCK 26.9 BOOKING 28.5 BOOKING 29.4 WEB 31.2 SPLIT 34.2 CUSTOM 35.6 ECO 38.3 LOCK 40.6" 5x6 renders/style-refine/vynic-launch-real-ui-contact-sheet.jpg
if [ -f "$film/$OLD" ]; then
  sheet "$OLD" "OLD-OPEN 3.4 OLD-POS 9.9 OLD-DATA 20.6 OLD-MGR 26.0 OLD-INV 32.4 OLD-SAAS 42.4 OLD-CUSTOM 50.2 OLD-ECO 54.6" 8x1 renders/style-refine/.old-row.jpg
  sheet "$OUT" "NEW-OPEN 1.3 NEW-POS 5.8 NEW-DATA 14.9 NEW-MGR 19.0 NEW-INV 23.3 NEW-SAAS 34.2 NEW-CUSTOM 35.6 NEW-ECO 38.3" 8x1 renders/style-refine/.new-row.jpg
  ff -i renders/style-refine/.old-row.jpg -i renders/style-refine/.new-row.jpg -filter_complex "[0][1]vstack=inputs=2" -q:v 3 renders/style-refine/vynic-launch-real-ui-old-vs-new.jpg
  rm -f "$film/renders/style-refine/.old-row.jpg" "$film/renders/style-refine/.new-row.jpg"
fi
echo "done: renders/style-refine/"
