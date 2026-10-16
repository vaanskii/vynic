// Vynic launch film: original music bed (no samples, no licensed material). 60.0s, 120 bpm (beat 0.5s).
// Arc: quiet opening → operational pulse (POS) → richer bed with bass (Manager) → lighter,
// bell-like arpeggio, no hats (websites) → gathering (ecosystem) → pulse stops, resolved D (lockup).
//   node audio/music.mjs  → assets/audio/music.wav
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { bus, render, hz, smooth, SR, TAU } from "./lib.mjs";

const DUR = 60.0, b = bus(DUR);
const chords = [
  [0.0, [50, 57, 62, 64, 66]],   // D add9
  [12.4, [47, 54, 57, 62, 66]],  // Bm7
  [18.2, [43, 50, 54, 57, 59]],  // Gmaj7
  [21.2, [45, 52, 57, 59, 64]],  // A sus
  [24.3, [40, 47, 54, 55, 62]],  // Em9 — Manager
  [28.3, [43, 50, 54, 57, 62]],  // Gmaj9
  [32.3, [47, 54, 57, 62, 66]],  // Bm7
  [36.3, [45, 52, 57, 59, 64]],  // A sus
  [38.6, [43, 50, 54, 57, 62]],  // Gmaj9 — websites
  [42.6, [42, 50, 54, 57, 62]],  // D/F#
  [46.6, [40, 47, 54, 55, 62]],  // Em9
  [50.6, [45, 52, 57, 61, 64]],  // A
  [52.7, [43, 50, 54, 57, 62]],  // Gmaj9 — ecosystem
  [54.7, [45, 52, 57, 59, 64]],  // A sus
  [57.6, [50, 57, 62, 64, 66, 69]], // D add9 — lockup
];
const chordAt = (t) => { let c = chords[0][1]; for (const [s, n] of chords) if (t >= s) c = n; return c; };

/* pad */
function padLevel(t) {
  if (t < 0.05) return 0;
  if (t < 3.0) return 0.1 * smooth(t / 3.0);
  if (t < 52.7) return 0.1 + 0.012 * Math.sin(t * 0.6);
  if (t < 56.6) return 0.1 + 0.05 * smooth((t - 52.7) / 3.9);
  if (t < 57.5) return 0.15 - 0.08 * smooth((t - 56.6) / 0.9);
  return 0.07 + 0.05 * smooth((t - 57.5) / 0.6);
}
const XF = 0.9;
for (let i = 0; i < b.N; i++) {
  const t = i / SR, lvl = padLevel(t); if (lvl <= 0) continue;
  let l = 0, r = 0;
  for (let c = 0; c < chords.length; c++) {
    const start = chords[c][0], end = c + 1 < chords.length ? chords[c + 1][0] : DUR + 1;
    const w = smooth((t - start + XF / 2) / XF) * (1 - smooth((t - end + XF / 2) / XF)); if (w <= 0) continue;
    chords[c][1].forEach((m, k) => {
      const f = hz(m), a = w / (k === 0 ? 1.3 : 1.9);
      const v1 = Math.sin(TAU * f * 1.0015 * t + k), v2 = Math.sin(TAU * f * 0.9985 * t + k * 2.1), h2 = 0.12 * Math.sin(TAU * f * 2 * t + k), pan = (k / 4 - 0.5) * 0.5;
      l += a * (v1 * (0.55 - pan) + h2); r += a * (v2 * (0.55 + pan) + h2);
    });
  }
  b.add(i, l * lvl, r * lvl, 0.35);
}
/* opening shimmer (very high, slow) */
for (let i = 0; i < Math.round(6.4 * SR); i++) {
  const t = i / SR, env = smooth(t / 2.0) * (1 - smooth((t - 4.8) / 1.6));
  const v = 0.006 * env * (Math.sin(TAU * hz(86) * t + 1.5 * Math.sin(TAU * 0.3 * t)) + 0.6 * Math.sin(TAU * hz(93) * t));
  b.add(i, v, v * 0.7, 0.8);
}
/* restrained pulse: a rounded low thump every beat pair, a ghost on the off-beat in Manager */
function thump(at, amp) {
  const f = hz(chordAt(at + 0.01)[0] - 12), n0 = Math.round(at * SR), len = Math.round(0.7 * SR);
  for (let j = 0; j < len; j++) { const t = j / SR, env = Math.min(1, t / 0.025) * Math.exp(-t / 0.22); const v = amp * env * (Math.sin(TAU * f * t) + 0.15 * Math.sin(TAU * f * 2 * t)); b.add(n0 + j, v, v, 0.04); }
}
for (let t = 6.4; t < 56.8; t += 1.0) {
  const ramp = smooth((t - 6.0) / 2.0), rich = t >= 24.3 && t < 38.6 ? 1.1 : t >= 38.6 && t < 52.7 ? 0.8 : 1.0;
  thump(t, 0.12 * ramp * rich);
  if (t >= 24.3 && t < 38.6) thump(t + 0.75, 0.05);
}
/* hats: filtered noise ticks on the off-beats (operational sections only) */
function hat(at, amp, pan) {
  const n0 = Math.round(at * SR), len = Math.round(0.08 * SR); let hp = 0, prev = 0;
  for (let j = 0; j < len; j++) { const t = j / SR, env = Math.min(1, t / 0.002) * Math.exp(-t / 0.018); const n = b.rnd() * 2 - 1; hp = 0.9 * (hp + n - prev); prev = n; const v = amp * env * hp; b.add(n0 + j, v * (1 - pan), v * (1 + pan), 0.15); }
}
for (let k = 0, t = 6.65; t < 56.8; k++, t += 0.5) {
  if (t >= 38.6 && t < 52.7) continue;
  hat(t, (k % 2 ? 0.014 : 0.02) * smooth((t - 6.4) / 3), k % 2 ? 0.3 : -0.3);
}
/* arpeggio: plucked eighths (POS, foundation, Manager), bell-like quarters (websites, ecosystem) */
function pluck(at, midi, amp, decay, pan) {
  const f = hz(midi), n0 = Math.round(at * SR), len = Math.round(decay * 4 * SR);
  for (let j = 0; j < len; j++) { const t = j / SR, env = Math.min(1, t / 0.003) * Math.exp(-t / decay); const v = amp * env * (Math.sin(TAU * f * t) + 0.3 * Math.sin(TAU * f * 2 * t) * Math.exp(-t / (decay * 0.4))); b.add(n0 + j, v * (1 - pan), v * (1 + pan), 0.45); }
}
const order = [0, 2, 1, 3, 2, 4, 1, 3];
for (let k = 0, t = 6.4; t < 56.8; k++) {
  const c = chordAt(t + 0.01).slice(-4).map((m) => m + 12), web = t >= 38.6;
  const note = c[order[k % order.length] % c.length];
  const amp = (web ? 0.028 : 0.022) * smooth((t - 6.4) / 2.5) * (t >= 24.3 && t < 38.6 ? 1.15 : 1);
  pluck(t, note, amp, web ? 0.55 : 0.16, k % 2 ? 0.25 : -0.25);
  t += web ? 0.5 : 0.25;
}
/* bass: from Manager on, root on the beat with a pickup */
for (let t = 24.3; t < 56.8; t += 2.0) {
  const root = chordAt(t + 0.01)[0] - 12;
  for (const [off, amp] of [[0, 0.1], [0.75, 0.05], [1.0, 0.07]]) {
    const f = hz(root), n0 = Math.round((t + off) * SR), len = Math.round(0.9 * SR);
    for (let j = 0; j < len; j++) { const tt = j / SR, env = Math.min(1, tt / 0.02) * Math.exp(-tt / 0.35); const v = amp * env * (Math.sin(TAU * f * tt) + 0.2 * Math.sin(TAU * f * 2 * tt)); b.add(n0 + j, v, v, 0.05); }
  }
}
const here = dirname(fileURLToPath(import.meta.url));
const rms = render(b, join(here, "..", "assets/audio/music.wav"), { peakDb: -6, fadeFrom: 59.2, fadeLen: 0.8 });
console.log(`music.wav · ${DUR}s · peak −6.0 dBFS · RMS ${rms.toFixed(1)} dBFS`);
