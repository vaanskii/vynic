// Georgian voice review (v2 script): every candidate voice reads every line as its own clip,
// plus the same short test passage, so voices and individual takes can be compared.
//
//   EDGE_TTS=/path/to/edge-tts node audio/voice-review.mjs [a b c]
//
// Output (git-ignored): renders/voice-review/
//   voice-<v>.wav             the shared test passage (lines 01–05 with designed pauses)
//   lines/<v>/voice_XX.wav    one clip per script line (trimmed, level-matched, 48 kHz stereo)
//   voice-<v>-script.wav      all lines placed at the proposed film timestamps (only when lines carry `start`)
//   stats.json                clip lengths and speaking rate per voice
// FFmpeg: $FFMPEG if set, otherwise the HyperFrames render image through Docker.
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const cfg = JSON.parse(readFileSync(join(here, "vo-v2-lines.json"), "utf8"));
const IMG = process.env.HF_IMG || "hyperframes-renderer:0.8.96-arm64";
const EDGE = process.env.EDGE_TTS || "edge-tts";
const outDir = join(root, "renders/voice-review");
const rawDir = join(outDir, ".raw");

// Mild "warm" chain: remove rumble, a little body around 160 Hz, soften the 3 kHz edge, gentle 2:1 levelling.
const WARM = "highpass=f=70,equalizer=f=160:t=q:w=1:g=2,equalizer=f=3300:t=q:w=1.2:g=-1.5,acompressor=threshold=-20dB:ratio=2:attack=15:release=120";
const VOICES = {
  a: { label: "Giorgi (Microsoft neural), engine defaults", voice: "ka-GE-GiorgiNeural", rate: "+0%", pitch: "+0Hz", chain: "" },
  b: { label: "Giorgi, directed: 6% slower, slightly lower, warm EQ", voice: "ka-GE-GiorgiNeural", rate: "-6%", pitch: "-3Hz", chain: WARM },
  c: { label: "Giorgi, deeper: 10% slower, lower pitch, warm EQ", voice: "ka-GE-GiorgiNeural", rate: "-10%", pitch: "-8Hz", chain: WARM },
};
const TARGET_LUFS = -18; // same as the film's voice stem

const ffCmd = (args) => process.env.FFMPEG
  ? [process.env.FFMPEG, args]
  : ["docker", ["run", "--rm", "--entrypoint", "ffmpeg", "-v", `${root}:/w`, IMG, ...args.map((a) => (a.startsWith(root) ? "/w/" + relative(root, a) : a))]];
const ff = (args) => execFileSync(...ffCmd(args), { stdio: ["ignore", "pipe", "pipe"] });
const ffStderr = (args) => spawnSync(...ffCmd(args), { encoding: "utf8" }).stderr || "";
const run = (args) => ff(["-hide_banner", "-loglevel", "error", "-y", ...args]);
const duration = (file) => {
  const out = ffStderr(["-hide_banner", "-i", file, "-f", "null", "-"]) ;
  const m = [...out.matchAll(/time=(\d+):(\d+):([\d.]+)/g)].pop();
  if (m) return +m[1] * 3600 + +m[2] * 60 + +m[3];
  const d = out.match(/Duration: (\d+):(\d+):([\d.]+)/);
  return d ? +d[1] * 3600 + +d[2] * 60 + +d[3] : NaN;
};
const measure = (file) => {
  const out = ffStderr(["-hide_banner", "-i", file, "-af", "ebur128=peak=true", "-f", "null", "-"]);
  const tail = out.slice(out.lastIndexOf("Summary:"));
  return { I: +tail.match(/I:\s+(-?[\d.]+) LUFS/)[1], peak: +tail.match(/Peak:\s+(-?[\d.]+) dBFS/)[1] };
};
const syllables = (s) => (s.match(/[აეიოუ]/g) || []).length; // Georgian: one vowel per syllable

const wanted = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(VOICES);
mkdirSync(rawDir, { recursive: true });
const stats = existsSync(join(outDir, "stats.json")) ? JSON.parse(readFileSync(join(outDir, "stats.json"), "utf8")) : {};

for (const key of wanted) {
  const v = VOICES[key];
  const lineDir = join(outDir, "lines", key);
  mkdirSync(lineDir, { recursive: true });
  const raw = {};

  // 1. Synthesize every line as its own clip.
  for (const line of cfg.lines) {
    const mp3 = join(rawDir, `${key}-${line.id}.mp3`);
    for (let attempt = 1; ; attempt++) {
      try {
        execFileSync(EDGE, ["--voice", v.voice, `--rate=${v.rate}`, `--pitch=${v.pitch}`, "--text", line.tts, "--write-media", mp3], { stdio: ["ignore", "ignore", "pipe"] });
        break;
      } catch (e) {
        if (attempt >= 5) throw e;
      }
    }
    raw[line.id] = mp3;
  }

  // 2. Trim edge silence (internal pauses are left exactly as spoken), apply the voice chain, 48 kHz stereo.
  for (const line of cfg.lines) {
    const trim = "silenceremove=start_periods=1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse";
    const chain = [trim, v.chain, "apad=pad_dur=0.04"].filter(Boolean).join(",");
    run(["-i", raw[line.id], "-af", chain, "-ar", "48000", "-ac", "2", join(lineDir, `${line.id}.pre.wav`)]);
  }

  // 3. One gain for the whole voice (measured over all lines together) so relative line dynamics survive; limit at −2 dBTP.
  const listFile = join(rawDir, `${key}-concat.txt`);
  writeFileSync(listFile, cfg.lines.map((l) => `file '${process.env.FFMPEG ? join(lineDir, l.id + ".pre.wav") : "/w/" + relative(root, join(lineDir, l.id + ".pre.wav"))}'`).join("\n"));
  const all = join(rawDir, `${key}-all.wav`);
  run(["-f", "concat", "-safe", "0", "-i", listFile, "-c", "copy", all]);
  const gain = TARGET_LUFS - measure(all).I;
  const lines = {};
  let speech = 0, syl = 0;
  for (const line of cfg.lines) {
    const pre = join(lineDir, `${line.id}.pre.wav`);
    const fin = join(lineDir, `${line.id}.wav`);
    run(["-i", pre, "-af", `volume=${gain.toFixed(2)}dB,alimiter=limit=0.79:level=false`, "-ar", "48000", "-ac", "2", fin]);
    rmSync(pre);
    const d = duration(fin);
    lines[line.id] = +d.toFixed(2);
    speech += d;
    syl += syllables(line.tts);
  }

  // 4. The shared test passage.
  const t = cfg.test;
  const ins = t.ids.flatMap((id) => ["-i", join(lineDir, `${id}.wav`)]);
  const pads = t.ids.map((id, i) => `[${i}:a]apad=pad_dur=${t.pauses[i] ?? 0}[p${i}]`).join(";");
  const cat = t.ids.map((_, i) => `[p${i}]`).join("") + `concat=n=${t.ids.length}:v=0:a=1,apad=pad_dur=0.6[o]`;
  run([...ins, "-filter_complex", `${pads};${cat}`, "-map", "[o]", "-ar", "48000", "-ac", "2", join(outDir, `voice-${key}.wav`)]);

  // 5. Full read at the proposed film timestamps (voice only; no music/SFX).
  if (cfg.lines.every((l) => typeof l.start === "number")) {
    const total = cfg.duration || 60;
    const ins2 = cfg.lines.flatMap((l) => ["-i", join(lineDir, `${l.id}.wav`)]);
    const del = cfg.lines.map((l, i) => `[${i}:a]adelay=${Math.round(l.start * 1000)}:all=1[d${i}]`).join(";");
    const mix = cfg.lines.map((_, i) => `[d${i}]`).join("") + `amix=inputs=${cfg.lines.length}:normalize=0,apad=whole_dur=${total}[o]`;
    run([...ins2, "-filter_complex", `${del};${mix}`, "-map", "[o]", "-t", String(total), "-ar", "48000", "-ac", "2", join(outDir, `voice-${key}-script.wav`)]);
  }

  stats[key] = { label: v.label, gainDb: +gain.toFixed(1), speechSeconds: +speech.toFixed(2), syllablesPerSecond: +(syl / speech).toFixed(2), passageSeconds: +duration(join(outDir, `voice-${key}.wav`)).toFixed(2), lines };
  console.log(`${key}\t${stats[key].speechSeconds}s speech\t${stats[key].syllablesPerSecond} syl/s\t${v.label}`);
}
writeFileSync(join(outDir, "stats.json"), JSON.stringify(stats, null, 2) + "\n");
rmSync(rawDir, { recursive: true, force: true });
