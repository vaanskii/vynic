#!/usr/bin/env bash
# Key frames from every scene of the rendered master → renders/contact-sheet_key-frames.jpg (4×5, labelled),
# plus a 720p quick-review copy of the master. Uses the FFmpeg inside the HyperFrames render image.
set -euo pipefail
IMG="${HF_IMG:-hyperframes-renderer:0.8.96-arm64}"
root="$(cd "$(dirname "$0")/.." && pwd)"
frames="1 1.2 1 2.2 1 2.9 2 3.6 2 4.5 2 6.3 2 7.6 3 8.4 3 9.9 4 11.3 4 12.8 4 13.9 4 14.9 4 16.3 5 18.0 5 18.8 5 19.6 5 21.0 6 22.3 6 24.8"
docker run --rm --entrypoint sh -v "$root/renders:/r" -v "$root/assets/fonts:/f" "$IMG" -c "
set -e; mkdir -p /r/.sheet; : > /r/.sheet/list.txt; set -- $frames; i=0
while [ \$# -gt 0 ]; do sc=\$1; t=\$2; shift 2; i=\$((i+1)); n=\$(printf %02d \$i)
  ffmpeg -hide_banner -loglevel error -y -ss \$t -i /r/vynic-film-master_1080p30.mp4 -frames:v 1 \
    -vf \"scale=640:-1,drawbox=x=0:y=0:w=150:h=34:color=black@0.6:t=fill,drawtext=fontfile=/f/Geist-SemiBold.ttf:text='S\$sc · \${t}s':x=12:y=9:fontsize=17:fontcolor=white\" /r/.sheet/\$n.png
  echo \"file '\$n.png'\" >> /r/.sheet/list.txt; done
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i /r/.sheet/list.txt -vf 'tile=4x5:padding=6:color=0x3a3533' -frames:v 1 -q:v 3 /r/contact-sheet_key-frames.jpg
ffmpeg -hide_banner -loglevel error -y -i /r/vynic-film-master_1080p30.mp4 -vf scale=1280:720 -c:v libx264 -crf 26 -preset medium -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart /r/vynic-film-quick-review_720p30.mp4
rm -rf /r/.sheet"
echo "renders/contact-sheet_key-frames.jpg · renders/vynic-film-quick-review_720p30.mp4"
