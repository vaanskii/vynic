// Vynic film score + sound design, synthesised from code (original, no samples).
// Deterministic: seeded noise, fixed cue table. Every cue time below is a
// timeline event in ../index.html; the pulse grid is 0.5s (120 bpm).
// Direction: a soft bed that breathes with the camera, deep accents on the
// camera moves, only the interactions that matter are audible.
//
//   node audio/synth.mjs            → assets/audio/vynic-score.wav (48 kHz, 16-bit, stereo)
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SR = 48000;
const DUR = 25.0;
const N = Math.round(SR * DUR);
const TAU = Math.PI * 2;

const L = new Float32Array(N), R = new Float32Array(N);
const sendL = new Float32Array(N), sendR = new Float32Array(N);

// Seeded PRNG (mulberry32) for noise.
let seed = 0x5eed1234;
function rnd() {
  seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

const hz = (m) => 440 * Math.pow(2, (m - 69) / 12); // MIDI → Hz
const smooth = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));
function add(i, l, r, send = 0) {
  if (i < 0 || i >= N) return;
  L[i] += l; R[i] += r; sendL[i] += l * send; sendR[i] += r * send;
}

/* ---------------- pad: chords follow the scenes ---------------- */
// D add9 (mark, POS) → Bm7 (handoff) → Em9 (Manager) → A sus (Inventory) → Gmaj9 (websites) → D (One Vynic).
const chords = [
  { t: 0.0, notes: [50, 57, 62, 64, 66] },      // D3 A3 D4 E4 F#4
  { t: 7.9, notes: [47, 54, 57, 62, 66] },      // B2 F#3 A3 D4 F#4
  { t: 10.3, notes: [40, 47, 54, 55, 62] },     // E2 B2 F#3 G3 D4
  { t: 13.35, notes: [45, 52, 57, 59, 64] },    // A2 E3 A3 B3 E4
  { t: 16.4, notes: [43, 50, 54, 57, 59] },     // G2 D3 F#3 A3 B3
  { t: 21.2, notes: [50, 57, 62, 66, 69] },     // D3 A3 D4 F#4 A4
];
function padLevel(t) {
  if (t < 0.05) return 0;
  if (t < 2.4) return 0.1 * smooth((t - 0.05) / 2.35);          // slower, atmospheric rise
  if (t < 21.2) return 0.1 + 0.012 * Math.sin(t * 0.7);
  if (t < 22.65) return 0.1 + 0.05 * smooth((t - 21.2) / 1.45); // overview swell
  if (t < 23.4) return 0.15 - 0.07 * smooth((t - 22.65) / 0.75); // fold inward
  if (t < 24.4) return 0.08 + 0.03 * smooth((t - 23.4) / 0.5);  // lockup chord
  return 0.11 * (1 - smooth((t - 24.4) / 0.6));
}
/* opening atmosphere: a very low filtered-noise "room" and a slow high shimmer under the mark */
{
  let lp = 0, lp2 = 0;
  const n0 = 0, len = Math.round(3.4 * SR);
  for (let j = 0; j < len; j++) {
    const t = j / SR;
    const env = smooth(t / 1.2) * (1 - smooth((t - 2.4) / 1.0));
    const a = 1 - Math.exp(-TAU * 260 / SR);
    lp += a * ((rnd() * 2 - 1) - lp); lp2 += a * (lp - lp2);
    const room = 0.09 * env * lp2 * 6;
    const sh = 0.006 * env * (Math.sin(TAU * 1760 * t + 2 * Math.sin(TAU * 0.4 * t)) + Math.sin(TAU * 2637 * t));
    add(n0 + j, room + sh, room - sh * 0.6, 0.6);
  }
}
const XF = 0.8; // slow chord crossfades
for (let i = 0; i < N; i++) {
  const t = i / SR;
  const lvl = padLevel(t);
  if (lvl <= 0) continue;
  let l = 0, r = 0;
  for (let c = 0; c < chords.length; c++) {
    const start = chords[c].t, end = c + 1 < chords.length ? chords[c + 1].t : DUR + 1;
    const w = smooth((t - start + XF / 2) / XF) * (1 - smooth((t - end + XF / 2) / XF));
    if (w <= 0) continue;
    chords[c].notes.forEach((m, k) => {
      const f = hz(m);
      const a = w / (k === 0 ? 1.3 : 1.9);
      const v1 = Math.sin(TAU * f * 1.0015 * t + k), v2 = Math.sin(TAU * f * 0.9985 * t + k * 2.1);
      const h2 = 0.12 * Math.sin(TAU * f * 2 * t + k);
      const pan = (k / 4 - 0.5) * 0.5;
      l += a * (v1 * (0.55 - pan) + h2);
      r += a * (v2 * (0.55 + pan) + h2);
    });
  }
  add(i, l * lvl, r * lvl, 0.35);
}

/* ---------------- soft rhythmic bed ---------------- */
// A rounded low pulse on every beat (1.0s) from the POS on, root follows the chord.
const roots = [[0, 38], [7.9, 35], [10.3, 40], [13.35, 33], [16.4, 31], [21.2, 38]]; // D2, B1, E2, A1, G1, D2
function rootAt(t) { let m = 38; for (const [s, n] of roots) if (t >= s) m = n; return hz(m); }
for (let bt = 3.8; bt < 22.6; bt += 1.0) {
  const f = rootAt(bt + 0.01);
  const amp = 0.1 * smooth((bt - 3.3) / 1.5) * (bt > 21.2 ? 1.15 : 1);
  const n0 = Math.round(bt * SR), len = Math.round(0.9 * SR);
  for (let j = 0; j < len; j++) {
    const t = j / SR;
    const env = Math.min(1, t / 0.03) * Math.exp(-t / 0.28);
    const v = amp * env * (Math.sin(TAU * f * t) + 0.18 * Math.sin(TAU * f * 2 * t));
    add(n0 + j, v, v, 0.05);
  }
}
// A brushed off-beat (filtered noise, very quiet) once the system is connected.
for (let k = 0, gt = 8.3; gt < 22.5; k++, gt += 1.0) {
  const n0 = Math.round(gt * SR), len = Math.round(0.12 * SR);
  const pan = k % 2 ? -0.3 : 0.3;
  let hp = 0, prev = 0;
  for (let j = 0; j < len; j++) {
    const t = j / SR;
    const env = Math.min(1, t / 0.004) * Math.exp(-t / 0.035);
    const n = rnd() * 2 - 1;
    hp = 0.86 * (hp + n - prev); prev = n;
    const v = 0.018 * env * hp;
    add(n0 + j, v * (1 - pan), v * (1 + pan), 0.2);
  }
}

/* ---------------- sound effects ---------------- */
function tone(at, freqs, dur, amp, decay, send = 0.4, pan = 0, attack = 0.004) {
  const n0 = Math.round(at * SR), len = Math.round(dur * SR);
  for (let j = 0; j < len; j++) {
    const t = j / SR;
    const env = Math.min(1, t / attack) * Math.exp(-t / decay);
    let v = 0;
    freqs.forEach(([f, a]) => { v += a * Math.sin(TAU * f * t); });
    v *= amp * env;
    add(n0 + j, v * (1 - pan), v * (1 + pan), send);
  }
}
function click(at, amp = 0.2, pan = 0) {
  tone(at, [[2600, 0.4], [880, 1]], 0.07, amp, 0.016, 0.2, pan, 0.002);
}
// Filtered noise swell with a moving two-pole low-pass (whoosh / swish / suck).
function air(at, dur, amp, fFrom, fTo, shape = "hump", send = 0.3) {
  const n0 = Math.round(at * SR), len = Math.round(dur * SR);
  let lp = 0, lp2 = 0;
  for (let j = 0; j < len; j++) {
    const x = j / len;
    const f = fFrom + (fTo - fFrom) * smooth(x);
    const a = 1 - Math.exp(-TAU * f / SR);
    const n = rnd() * 2 - 1;
    lp += a * (n - lp); lp2 += a * (lp - lp2);
    const env = shape === "rise" ? Math.pow(x, 2.2) * (1 - smooth((x - 0.92) / 0.08))
      : shape === "draw" ? Math.sin(Math.PI * Math.min(1, x * 1.15)) * (1 - x * 0.4)
      : Math.pow(Math.sin(Math.PI * x), 1.6);
    const v = amp * env * (lp - lp2 * 0.35) * 3;
    add(n0 + j, v * (1 - 0.2 * Math.sin(x * 3)), v * (1 + 0.2 * Math.sin(x * 3)), send);
  }
}
function glide(at, dur, f0, f1, amp, send = 0.45) {
  const n0 = Math.round(at * SR), len = Math.round(dur * SR);
  let ph = 0;
  for (let j = 0; j < len; j++) {
    const x = j / len;
    const f = f0 * Math.pow(f1 / f0, smooth(x));
    ph += TAU * f / SR;
    const env = Math.pow(Math.sin(Math.PI * x), 1.4);
    const v = amp * env * (Math.sin(ph) + 0.25 * Math.sin(ph * 2.01));
    add(n0 + j, v, v, send);
  }
}
function chime(at, midi, amp, decay = 1.1, send = 0.55) {
  const f = hz(midi);
  tone(at, [[f, 1], [f * 2.0, 0.35], [f * 3.01, 0.12], [f * 4.2, 0.05]], decay * 3, amp, decay, send, 0, 0.002);
}
// Deep transition accent: a low, slow swell that peaks where the camera decelerates.
function move(at, dur, amp = 0.06) {
  air(at, dur, amp, 110, 1300, "hump", 0.35);
  glide(at + dur * 0.15, dur * 0.8, 55, 82, amp * 0.9, 0.2);
}
// Restrained low-frequency impact (sub with a soft attack, no click).
function sub(at, f, amp, decay) {
  tone(at, [[f, 1], [f * 2, 0.22]], decay * 4, amp, decay, 0.25, 0, 0.02);
}

// 1 · the mark → the POS (one shot)
chime(0.2, 93, 0.035, 1.3);                         // spark (A6), longer tail
air(0.45, 0.8, 0.04, 700, 4200, "draw");            // thick stroke draws
air(0.95, 0.7, 0.03, 1100, 5200, "draw");           // thin stroke draws
air(1.25, 1.0, 0.03, 180, 1600);                    // wordmark arrives with depth
sub(1.3, 49, 0.1, 0.4);                             // soft low bloom under it
glide(1.6, 0.75, 1400, 2800, 0.009, 0.7);           // light travels through the mark
chime(1.65, 86, 0.018, 1.5);                        // D6 shimmer as it turns white
move(2.2, 1.4, 0.05);                               // the camera leaves the mark
glide(2.3, 1.05, 700, 1050, 0.008, 0.6);            // the stroke extends and traces the window

// camera travel accents (deep, not whooshy)
move(8.25, 1.4, 0.045);
move(16.4, 1.5, 0.045);
move(21.2, 1.25, 0.055);

// 2 · POS: only the moments that matter, all soft
click(4.45, 0.075, -0.1);                            // Table 4
tone(7.45, [[hz(76), 1], [hz(88), 0.25]], 0.5, 0.05, 0.12, 0.45);   // E5 …
tone(7.6, [[hz(81), 1], [hz(93), 0.2]], 0.9, 0.05, 0.22, 0.5);      // … A5, sent to kitchen

// 3 · handoff: one restrained transition, POS → record → Manager
glide(8.75, 1.1, 330, 660, 0.016);                   // capsule to the record
chime(9.85, 88, 0.04, 1.3);                          // E6 dock
chime(9.855, 83, 0.024, 1.4);                        // B5
air(10.3, 1.5, 0.045, 120, 1500, "hump", 0.35);      // the camera follows the figure
glide(10.45, 1.45, 440, 880, 0.013);
sub(11.85, 52, 0.07, 0.3);                           // it lands on the revenue card

// 4 · Manager
chime(12.45, 83, 0.035, 1.1);                        // figures land after refresh (B5)
click(13.15, 0.04, 0.15);                            // open Inventory (barely there)
tone(15.3, [[hz(69), 1], [hz(76), 0.5]], 0.7, 0.045, 0.16, 0.4);    // quiet Inventory cue: receiving confirmed
chime(15.95, 81, 0.02, 1.2);                         // stock + debt follow (A5, soft)

// 5 · Websites
glide(16.95, 0.8, 500, 1000, 0.014);                 // menu pulse
air(18.5, 0.6, 0.02, 400, 2400);                     // the dish lifts
air(18.9, 1.3, 0.045, 600, 5200, "hump", 0.55);      // the renderer changes beneath it
chime(20.25, 79, 0.028, 1.5);                        // G5 as it settles into the custom menu
air(20.4, 0.9, 0.028, 250, 1800);                    // SaaS window returns

// 6 · One Vynic
glide(21.75, 0.8, 600, 1200, 0.014);                 // outward pulses
air(22.6, 0.7, 0.055, 300, 3400, "rise", 0.3);       // fold inward
sub(23.4, 55, 0.2, 0.55);                            // restrained lockup impact (A1)
chime(23.4, 74, 0.04, 1.6);                          // D5
chime(23.41, 81, 0.03, 1.6);                         // A5
chime(23.42, 90, 0.018, 1.4);                        // F#6

/* ---------------- reverb (Schroeder) on the send ---------------- */
function reverb(inp, combs, aps, fb = 0.8, damp = 0.25) {
  const out = new Float32Array(N);
  for (const d of combs) {
    const buf = new Float32Array(d); let idx = 0, last = 0;
    for (let i = 0; i < N; i++) {
      const y = buf[idx];
      last = y * (1 - damp) + last * damp;
      buf[idx] = inp[i] + last * fb;
      idx = (idx + 1) % d;
      out[i] += y;
    }
  }
  for (const d of aps) {
    const buf = new Float32Array(d); let idx = 0;
    for (let i = 0; i < N; i++) {
      const b = buf[idx], x = out[i];
      const y = -x + b;
      buf[idx] = x + b * 0.5;
      idx = (idx + 1) % d;
      out[i] = y;
    }
  }
  return out;
}
const s = SR / 44100;
const wetL = reverb(sendL, [1557, 1617, 1491, 1422].map((d) => Math.round(d * s)), [225, 556].map((d) => Math.round(d * s)));
const wetR = reverb(sendR, [1580, 1640, 1514, 1445].map((d) => Math.round(d * s)), [248, 579].map((d) => Math.round(d * s)));

/* ---------------- master ---------------- */
const out = new Int16Array(N * 2);
let peak = 0;
const mixL = new Float32Array(N), mixR = new Float32Array(N);
for (let i = 0; i < N; i++) {
  const t = i / SR;
  const fade = t > 24.4 ? 1 - smooth((t - 24.4) / 0.6) : 1;
  const fadeIn = Math.min(1, t / 0.01);
  mixL[i] = Math.tanh((L[i] + wetL[i] * 0.09) * 1.1) * fade * fadeIn;
  mixR[i] = Math.tanh((R[i] + wetR[i] * 0.09) * 1.1) * fade * fadeIn;
  peak = Math.max(peak, Math.abs(mixL[i]), Math.abs(mixR[i]));
}
const gain = Math.pow(10, -3 / 20) / peak; // peak −3 dBFS
let sumSq = 0;
for (let i = 0; i < N; i++) {
  const l = mixL[i] * gain, r = mixR[i] * gain;
  sumSq += l * l + r * r;
  out[i * 2] = Math.round(Math.max(-1, Math.min(1, l)) * 32767);
  out[i * 2 + 1] = Math.round(Math.max(-1, Math.min(1, r)) * 32767);
}

const here = dirname(fileURLToPath(import.meta.url));
const file = join(here, "..", "assets", "audio", "vynic-score.wav");
mkdirSync(dirname(file), { recursive: true });
const header = Buffer.alloc(44);
const dataBytes = out.length * 2;
header.write("RIFF", 0); header.writeUInt32LE(36 + dataBytes, 4); header.write("WAVE", 8);
header.write("fmt ", 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(2, 22);
header.writeUInt32LE(SR, 24); header.writeUInt32LE(SR * 4, 28); header.writeUInt16LE(4, 32); header.writeUInt16LE(16, 34);
header.write("data", 36); header.writeUInt32LE(dataBytes, 40);
writeFileSync(file, Buffer.concat([header, Buffer.from(out.buffer)]));
const rmsDb = 10 * Math.log10(sumSq / (N * 2));
console.log(`wrote ${file} · ${DUR}s · peak −3.0 dBFS · RMS ${rmsDb.toFixed(1)} dBFS`);
