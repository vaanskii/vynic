# Vynic launch film (HyperFrames, 60 s, Georgian)

This is the official launch film. It is separate from the 25 s product film in `../vynic-product-film/`, which stays the website-hero candidate. It tells one restaurant's story: POS service → one foundation → Manager (day + Inventory) → online (SaaS → Custom/Vankisi) → one ecosystem → Vynic.

| File | What it is |
|---|---|
| `BRIEF.md` | Intent and truth constraints |
| `STORYBOARD.md` | Seven scenes with exact timestamps; final-line options |
| `CAPTIONS_GE.md` | **Current:** the on-screen Georgian captions (text, timing, meaning, claims check). The film has no narration. |
| `VOICEOVER_GE.md` | Superseded: the earlier narrated version's script (the voice was removed in favour of captions) |
| `VOICEOVER_TIMING.md` | Line-by-line placement and music-only breaths |
| `VOICEOVER_GE_V2.md` | v2 script proposal (silent opening, no spoken technical English, 16 phrase clips) and the voice review |
| `MOTION_DIRECTION.md` | Palette, type, camera and motion |
| `index.html` + `film.css` | The composition: one world, one camera, one paused timeline |
| `audio/` | `tts.mjs` (temporary voice), `music.mjs`, `sfx.mjs`, `lib.mjs` (original synthesis) |
| `tools/deliver.sh` | Loudness, music-only master, muted web, review, stems, contact sheet |

## Commands

```bash
npm run audio           # regenerate music.wav + sfx.wav (deterministic)
EDGE_TTS=/path/to/edge-tts npm run tts   # regenerate temporary Georgian voice lines (+ loudness pass)
EDGE_TTS=/path/to/edge-tts npm run voice:review   # v2 voice review → renders/voice-review/
npm run check           # lint + runtime + layout + motion + contrast
npm run render:master   # 4K supersampled Docker render (music + SFX; captions carry the story)
npm run deliver         # 1080p/2160p masters, muted web versions, review, stems, contact sheet
npm run render          # both
```

Renders use Docker (image `hyperframes-renderer:0.8.96-arm64`); no host FFmpeg is needed. The master is rendered at 4K (`--resolution landscape-4k`) and downscaled, so small UI text stays sharp in the 1080p files. The `tts` and `voice:review` scripts belong to the superseded narrated version.

## Outputs (git-ignored)

- `renders/vynic-launch-master_1080p30.mp4` and `_2160p30.mp4`: master with music and SFX.
- `renders/vynic-launch-web_1080p30.mp4`: **main website version**, with background music and no narration.
- `renders/vynic-launch-web-muted_1080p30.mp4` and `_2160p30.mp4`: fully muted versions, for silent autoplay.
- `renders/vynic-launch-review_720p30.mp4`, `renders/vynic-launch-contact-sheet.jpg`.
- `stems/`: `music.wav`, `sfx.wav`, `master-mix.wav`.
