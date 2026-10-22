// Temporary Georgian voice-over: one file per line (assets/audio/vo/<id>.wav, 48 kHz mono→stereo).
// Engine: Microsoft Edge neural TTS (ka-GE-GiorgiNeural) via the open-source `edge-tts` CLI.
// Replace any line by dropping a new <id>.wav in place; the composition places lines by id.
//   EDGE_TTS=/path/to/edge-tts node audio/tts.mjs
import { readFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const cfg = JSON.parse(readFileSync(join(here, "vo-lines.json"), "utf8"));
const tts = process.env.EDGE_TTS || "edge-tts";
const IMG = process.env.HF_IMG || "hyperframes-renderer:0.8.96-arm64";
const out = join(root, "assets/audio/vo");
mkdirSync(out, { recursive: true });
const only = process.argv.slice(2); // optional: regenerate just these ids
for (const line of cfg.lines) {
  if (only.length ? !only.includes(line.id) : existsSync(join(out, line.id + ".wav"))) continue;
  const mp3 = join(out, line.id + ".mp3");
  for (let attempt = 1; ; attempt++) {
    try {
      execFileSync(tts, ["--voice", cfg.voice, `--rate=${cfg.rate}`, `--pitch=${cfg.pitch}`, "--text", line.tts, "--write-media", mp3], { stdio: ["ignore", "ignore", "pipe"] });
      break;
    } catch (e) {
      if (attempt >= 5) throw e;
      console.error(`${line.id}: TTS attempt ${attempt} failed, retrying`);
    }
  }
  // Trim leading/trailing silence, cap internal pauses at ~0.45s, 48 kHz stereo WAV (FFmpeg from the HyperFrames render image).
  execFileSync("docker", ["run", "--rm", "--entrypoint", "ffmpeg", "-v", `${out}:/v`, IMG, "-hide_banner", "-loglevel", "error", "-y", "-i", `/v/${line.id}.mp3`,
    "-af", "silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=stop_periods=-1:stop_duration=0.5:stop_threshold=-45dB:stop_silence=0.45,apad=pad_dur=0.05",
    "-ar", "48000", "-ac", "2", `/v/${line.id}.wav`]);
  rmSync(mp3);
  const dur = execFileSync("docker", ["run", "--rm", "--entrypoint", "ffprobe", "-v", `${out}:/v`, IMG, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", `/v/${line.id}.wav`]).toString().trim();
  console.log(`${line.id}\t${Number(dur).toFixed(2)}s\t${line.text}`);
}

// Loudness pass for every line present (also run after hand-replacing lines):
// about −18 LUFS integrated, −2 dBTP, so the voice sits above the carved bed.
for (const line of cfg.lines) {
  const wav = join(out, line.id + ".wav");
  if (!existsSync(wav)) continue;
  execFileSync("docker", ["run", "--rm", "--entrypoint", "ffmpeg", "-v", `${out}:/v`, IMG, "-hide_banner", "-loglevel", "error", "-y", "-i", `/v/${line.id}.wav`,
    "-af", "loudnorm=I=-18:TP=-2:LRA=7", "-ar", "48000", "-ac", "2", `/v/${line.id}.norm.wav`]);
  execFileSync("mv", [join(out, line.id + ".norm.wav"), wav]);
}
console.log("voice lines normalised (−18 LUFS, −2 dBTP)");
