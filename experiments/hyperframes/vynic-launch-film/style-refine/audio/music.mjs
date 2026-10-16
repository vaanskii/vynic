// Fast-motion refine: original music (no samples, no licensed material). 32.2 s, 120 bpm (beat 0.5 s), D major.
// Cut to the picture: riser → plum hit → drive (POS) → wipe impact → data (one system) → full drive (Manager)
// → lighter bells (web) → transform swell → build (ecosystem) → gap → final hit, resolved D.
//   node audio/music.mjs → assets/audio/music.wav
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { bus, render, hz, smooth, SR, TAU, air } from "../../audio/lib.mjs";

const DUR = 32.2, b = bus(DUR);
const chords = [
  [0.0, [50, 57, 62, 64, 66]], [4.5, [47, 54, 57, 62, 66]], [6.7, [45, 52, 57, 59, 64]],
  [7.6, [40, 47, 54, 55, 62]], [8.6, [43, 50, 54, 57, 62]], [10.6, [47, 54, 57, 62, 66]],
  [12.6, [45, 52, 57, 59, 64]], [14.6, [43, 50, 54, 57, 62]], [16.6, [42, 50, 54, 57, 62]],
  [18.6, [45, 52, 57, 59, 64]], [19.7, [43, 50, 54, 57, 62]], [21.7, [42, 50, 54, 57, 62]],
  [23.1, [40, 47, 54, 55, 62]], [24.3, [47, 54, 57, 62, 66]], [25.7, [43, 50, 54, 57, 62]],
  [26.6, [45, 52, 57, 59, 64]], [29.2, [50, 57, 62, 64, 66, 69]],
];
const chordAt = (t) => { let c = chords[0][1]; for (const [s, n] of chords) if (t >= s) c = n; return c; };
const inRange = (t, a, z) => t >= a && t < z;

/* pad: present but lower than the old bed; dips in the gap before the final hit */
function padLevel(t) {
  if (t < 1.0) return 0.035 * smooth(t / 1.0);
  if (t < 28.75) return 0.07;
  if (t < 29.2) return 0.07 * (1 - smooth((t - 28.75) / 0.3));
  return 0.11 * smooth((t - 29.2) / 0.08);
}
const XF = 0.25;
for (let i = 0; i < b.N; i++) {
  const t = i / SR, lvl = padLevel(t); if (lvl <= 0) continue;
  let l = 0, r = 0;
  for (let c = 0; c < chords.length; c++) {
    const start = chords[c][0], end = c + 1 < chords.length ? chords[c + 1][0] : DUR + 1;
    const w = smooth((t - start + XF / 2) / XF) * (1 - smooth((t - end + XF / 2) / XF)); if (w <= 0) continue;
    chords[c][1].forEach((m, k) => {
      const f = hz(m), a = w / (k === 0 ? 1.3 : 1.9), pan = (k / 4 - 0.5) * 0.6;
      const v1 = Math.sin(TAU * f * 1.002 * t + k), v2 = Math.sin(TAU * f * 0.998 * t + k * 2.1), h2 = 0.18 * Math.sin(TAU * f * 2 * t + k);
      l += a * (v1 * (0.55 - pan) + h2); r += a * (v2 * (0.55 + pan) + h2);
    });
  }
  b.add(i, l * lvl, r * lvl, 0.3);
}

/* drums */
function kick(at, amp) {
  const n0 = Math.round(at * SR), len = Math.round(0.32 * SR); let ph = 0;
  for (let j = 0; j < len; j++) { const t = j / SR, f = 46 + 90 * Math.exp(-t / 0.035); ph += TAU * f / SR;
    const env = Math.min(1, t / 0.002) * Math.exp(-t / 0.12); const v = amp * env * Math.sin(ph); b.add(n0 + j, v, v, 0.02); }
}
function hat(at, amp, pan, dec = 0.018) {
  const n0 = Math.round(at * SR), len = Math.round(0.09 * SR); let hp = 0, prev = 0;
  for (let j = 0; j < len; j++) { const t = j / SR, env = Math.min(1, t / 0.001) * Math.exp(-t / dec); const n = b.rnd() * 2 - 1; hp = 0.92 * (hp + n - prev); prev = n; const v = amp * env * hp; b.add(n0 + j, v * (1 - pan), v * (1 + pan), 0.12); }
}
function clap(at, amp) {
  const n0 = Math.round(at * SR), len = Math.round(0.22 * SR); let bp = 0, lp = 0;
  for (let j = 0; j < len; j++) { const t = j / SR, burst = t < 0.03 ? (Math.floor(t / 0.01) % 2 ? 0.6 : 1) : 1, env = Math.min(1, t / 0.002) * Math.exp(-t / 0.07) * burst;
    const n = b.rnd() * 2 - 1; lp += 0.35 * (n - lp); bp = n - lp; const v = amp * env * bp; b.add(n0 + j, v * 0.9, v, 0.3); }
}
for (let t = 2.5; t < 28.8; t += 0.5) {
  const drive = inRange(t, 2.5, 6.7) ? 1 : inRange(t, 7.6, 10.1) ? (Math.round((t - 7.6) * 2) % 2 ? 0 : 0.85) : inRange(t, 10.6, 19.2) ? 1.1
    : inRange(t, 19.7, 26.6) ? 0.7 : inRange(t, 26.6, 28.8) ? 1.15 : 0;
  if (drive > 0) kick(t, 0.32 * drive);
  if (inRange(t, 10.6, 19.2) && Math.round((t - 10.6) * 2) % 2 === 1) clap(t, 0.07);
}
for (let k = 0, t = 1.0; t < 28.8; k++, t += 0.125) {
  const lvl = t < 2.5 ? 0.006 + 0.01 * smooth((t - 1) / 1.5) : inRange(t, 6.7, 7.6) ? 0 : inRange(t, 19.7, 26.6) ? (k % 2 ? 0 : 0.008) : 0.012 + (k % 4 === 2 ? 0.01 : 0);
  if (lvl > 0) hat(t, lvl * (inRange(t, 26.6, 28.8) ? 1 + (t - 26.6) * 0.35 : 1), k % 2 ? 0.35 : -0.35);
}
/* snare roll into the collapse */
for (let t = 27.8, d = 0.125; t < 28.75; t += d, d = Math.max(0.045, d * 0.86)) clap(t, 0.03 + 0.05 * smooth((t - 27.8) / 0.95));

/* bass: 8ths on the drive, syncopated in Manager */
function bass(at, midi, amp, len = 0.22) {
  const f = hz(midi), n0 = Math.round(at * SR), L = Math.round(len * 1.6 * SR);
  for (let j = 0; j < L; j++) { const t = j / SR, env = Math.min(1, t / 0.006) * Math.exp(-t / len); const v = amp * env * (Math.sin(TAU * f * t) + 0.35 * Math.sin(TAU * f * 2 * t) + 0.12 * Math.sin(TAU * f * 3 * t)); b.add(n0 + j, v, v, 0.03); }
}
for (let t = 2.5; t < 28.8; t += 0.25) {
  const on = inRange(t, 2.5, 6.7) || inRange(t, 7.6, 10.1) || inRange(t, 10.6, 19.2) || inRange(t, 26.6, 28.8) || (inRange(t, 19.7, 26.6) && Math.round((t - 19.7) * 4) % 4 === 0);
  if (!on) continue;
  const root = chordAt(t + 0.01)[0] - 12, step = Math.round(t * 4) % 8;
  const syn = inRange(t, 10.6, 19.2) ? [1, 0, 0.6, 1, 0, 0.7, 1, 0.5][step] : [1, 0.5, 0.8, 0.5, 1, 0.5, 0.8, 0.5][step];
  if (syn) bass(t, root + (step === 7 && inRange(t, 10.6, 19.2) ? 7 : 0), 0.085 * syn);
}

/* arps: plucked 16ths on the drive; bells in the web section */
function pluck(at, midi, amp, decay, pan) {
  const f = hz(midi), n0 = Math.round(at * SR), len = Math.round(decay * 4 * SR);
  for (let j = 0; j < len; j++) { const t = j / SR, env = Math.min(1, t / 0.002) * Math.exp(-t / decay); const v = amp * env * (Math.sin(TAU * f * t) + 0.35 * Math.sin(TAU * f * 2 * t) * Math.exp(-t / (decay * 0.4))); b.add(n0 + j, v * (1 - pan), v * (1 + pan), 0.4); }
}
const order = [0, 2, 1, 3, 2, 4, 1, 3];
for (let k = 0, t = 1.0; t < 28.8; k++) {
  const web = inRange(t, 19.7, 26.6), gap = inRange(t, 6.7, 7.6) || inRange(t, 10.1, 10.6) || inRange(t, 19.2, 19.7);
  if (!gap) {
    const c = chordAt(t + 0.01).slice(-4).map((m) => m + (web ? 24 : 12));
    const amp = (web ? 0.026 : 0.018) * (t < 2.5 ? smooth((t - 1) / 1.5) : 1) * (inRange(t, 10.6, 19.2) ? 1.15 : 1);
    pluck(t, c[order[k % order.length] % c.length], amp, web ? 0.4 : 0.09, k % 2 ? 0.3 : -0.3);
  }
  t += web ? 0.25 : 0.125;
}

/* transition swells (musical side; the one-shot hits live in sfx) */
air(b, 0.0, 1.05, 0.03, 900, 5200, "rise", 0.5);
air(b, 6.2, 0.62, 0.04, 700, 6000, "rise", 0.3);
air(b, 9.75, 0.7, 0.035, 700, 6000, "rise", 0.3);
air(b, 18.75, 0.95, 0.04, 600, 6500, "rise", 0.3);
air(b, 22.3, 1.9, 0.04, 500, 7000, "rise", 0.5);
air(b, 27.8, 1.4, 0.05, 500, 7500, "rise", 0.3);
/* final: resolved D with a low octave */
for (const [m, a] of [[38, 0.14], [50, 0.08]]) {
  const f = hz(m), n0 = Math.round(29.2 * SR), len = Math.round(4.2 * SR);
  for (let j = 0; j < len; j++) { const t = j / SR, env = Math.min(1, t / 0.01) * Math.exp(-t / 1.6); const v = a * env * Math.sin(TAU * f * t); b.add(n0 + j, v, v, 0.15); }
}

const here = dirname(fileURLToPath(import.meta.url));
const rms = render(b, join(here, "..", "assets/audio/music.wav"), { peakDb: -4, wet: 0.08, fadeFrom: 31.4, fadeLen: 0.8 });
console.log(`music.wav · ${DUR}s · peak −4.0 dBFS · RMS ${rms.toFixed(1)} dBFS`);
