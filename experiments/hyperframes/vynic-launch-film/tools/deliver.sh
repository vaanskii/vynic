#!/usr/bin/env bash
# Everything after the one HyperFrames render (renders/vynic-launch-master_2160p30.mp4, rendered at 4K
# so thin UI text is supersampled; see package.json "render:master"):
#   A. master 1080p + 2160p (music + SFX; the story is told by on-screen captions, no narration)
#   B. website version with music (1080p)
#   C. muted website versions (1080p and 2160p, H.264, no audio track; for silent autoplay)
#   D. review version (720p, with sound)
#   stems/ music.wav · sfx.wav · master-mix.wav
#   E. contact sheet of every major state
# Uses the FFmpeg inside the HyperFrames render image (no host FFmpeg needed).
set -euo pipefail
IMG="${HF_IMG:-hyperframes-renderer:0.8.96-arm64}"
root="$(cd "$(dirname "$0")/.." && pwd)"
ff() { docker run --rm -v "$root:/p" -w /p --entrypoint ffmpeg "$IMG" -hide_banner -loglevel error -y "$@"; }
SRC=renders/vynic-launch-master_2160p30.mp4
M=renders/vynic-launch-master_1080p30.mp4
test -f "$root/$SRC" || { echo "render the master first: npm run render:master"; exit 1; }
mkdir -p "$root/stems" "$root/renders"
# 4K → 1080p with Lanczos: the supersampled source keeps small UI text crisp.
DOWN="scale=1920:1080:flags=lanczos+accurate_rnd+full_chroma_int"
X264="-c:v libx264 -preset slow -tune animation -pix_fmt yuv420p -profile:v high -g 60 -movflags +faststart"

# Loudness: bring the music + SFX mix to a launch-film level (about −16 LUFS, −1.5 dBTP). 4K picture is stream-copied.
ff -i "$SRC" -map 0:v:0 -map 0:a:0 -c:v copy -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ar 48000 -c:a aac -b:a 256k -movflags +faststart renders/.master-norm.mp4
mv "$root/renders/.master-norm.mp4" "$root/$SRC"

# A. 1080p master (high quality, with sound)
ff -i "$SRC" -vf "$DOWN" $X264 -crf 14 -c:a copy "$M"
# B. website version WITH music (+ subtle SFX), no narration: the main version for use
ff -i "$SRC" -vf "$DOWN" $X264 -crf 18 -c:a aac -b:a 192k renders/vynic-launch-web_1080p30.mp4
# C. muted website versions: 1080p (default) and 2160p (for large / high-density screens)
ff -i "$SRC" -map 0:v:0 -an -vf "$DOWN" $X264 -crf 18 renders/vynic-launch-web-muted_1080p30.mp4
ff -i "$SRC" -map 0:v:0 -an $X264 -crf 20 renders/vynic-launch-web-muted_2160p30.mp4
# D. review version
ff -i "$SRC" -vf "scale=1280:720:flags=lanczos" -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart renders/vynic-launch-review_720p30.mp4

# stems
cp "$root/assets/audio/music.wav" "$root/stems/music.wav"
cp "$root/assets/audio/sfx.wav" "$root/stems/sfx.wav"
ff -i "$M" -vn -ar 48000 -ac 2 stems/master-mix.wav
echo "stems: music.wav sfx.wav master-mix.wav"

# E. contact sheet (scene · time)
frames="1 1.2 1 2.4 1 3.4 1 5.0 2 6.9 2 8.2 2 9.9 2 11.4 2 12.4 2 15.0 3 18.8 3 20.6 3 22.2 4 23.7 4 25.9 4 28.6 4 30.8 4 32.2 4 34.6 4 36.6 5 40.6 5 42.4 5 43.9 5 45.3 5 46.9 5 48.4 5 50.2 5 51.8 6 54.6 7 59.4"
docker run --rm --entrypoint sh -v "$root:/p" -w /p "$IMG" -c "
set -e; rm -rf renders/.sheet; mkdir -p renders/.sheet; : > renders/.sheet/list.txt; set -- $frames; i=0
while [ \$# -gt 0 ]; do sc=\$1; t=\$2; shift 2; i=\$((i+1)); n=\$(printf %02d \$i)
  ffmpeg -hide_banner -loglevel error -y -ss \$t -i $M -frames:v 1 -vf \"scale=480:-1,drawbox=x=0:y=0:w=118:h=28:color=black@0.6:t=fill,drawtext=fontfile=assets/fonts/Geist-SemiBold.ttf:text='S\$sc · \${t}s':x=9:y=7:fontsize=14:fontcolor=white\" renders/.sheet/\$n.png
  echo \"file '\$n.png'\" >> renders/.sheet/list.txt; done
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i renders/.sheet/list.txt -vf 'tile=5x6:padding=6:color=0x3a3533' -frames:v 1 -q:v 3 renders/vynic-launch-contact-sheet.jpg
rm -rf renders/.sheet"
echo "done: renders/ (master 1080p/2160p, web-muted 1080p/2160p, review, contact sheet) and stems/"
