// Tiny deterministic synth kit shared by music.mjs and sfx.mjs (48 kHz stereo, float → 16-bit WAV).
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

export const SR = 48000;
export const TAU = Math.PI * 2;
export const hz = (m) => 440 * Math.pow(2, (m - 69) / 12);
export const smooth = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x));

export function bus(dur) {
  const N = Math.round(SR * dur);
  const b = { N, dur, L: new Float32Array(N), R: new Float32Array(N), sL: new Float32Array(N), sR: new Float32Array(N), seed: 0x5eed1234 };
  b.rnd = () => { b.seed |= 0; b.seed = (b.seed + 0x6d2b79f5) | 0; let t = Math.imul(b.seed ^ (b.seed >>> 15), 1 | b.seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  b.add = (i, l, r, send = 0) => { if (i < 0 || i >= N) return; b.L[i] += l; b.R[i] += r; b.sL[i] += l * send; b.sR[i] += r * send; };
  return b;
}
export function tone(b, at, freqs, dur, amp, decay, send = 0.4, pan = 0, attack = 0.004) {
  const n0 = Math.round(at * SR), len = Math.round(dur * SR);
  for (let j = 0; j < len; j++) {
    const t = j / SR, env = Math.min(1, t / attack) * Math.exp(-t / decay);
    let v = 0; for (const [f, a] of freqs) v += a * Math.sin(TAU * f * t);
    v *= amp * env; b.add(n0 + j, v * (1 - pan), v * (1 + pan), send);
  }
}
export function air(b, at, dur, amp, fFrom, fTo, shape = "hump", send = 0.3) {
  const n0 = Math.round(at * SR), len = Math.round(dur * SR);
  let lp = 0, lp2 = 0;
  for (let j = 0; j < len; j++) {
    const x = j / len, f = fFrom + (fTo - fFrom) * smooth(x), a = 1 - Math.exp(-TAU * f / SR);
    lp += a * ((b.rnd() * 2 - 1) - lp); lp2 += a * (lp - lp2);
    const env = shape === "rise" ? Math.pow(x, 2.2) * (1 - smooth((x - 0.92) / 0.08)) : shape === "draw" ? Math.sin(Math.PI * Math.min(1, x * 1.15)) * (1 - x * 0.4) : Math.pow(Math.sin(Math.PI * x), 1.6);
    const v = amp * env * (lp - lp2 * 0.35) * 3;
    b.add(n0 + j, v * (1 - 0.2 * Math.sin(x * 3)), v * (1 + 0.2 * Math.sin(x * 3)), send);
  }
}
export function glide(b, at, dur, f0, f1, amp, send = 0.45) {
  const n0 = Math.round(at * SR), len = Math.round(dur * SR); let ph = 0;
  for (let j = 0; j < len; j++) {
    const x = j / len, f = f0 * Math.pow(f1 / f0, smooth(x)); ph += TAU * f / SR;
    const v = amp * Math.pow(Math.sin(Math.PI * x), 1.4) * (Math.sin(ph) + 0.25 * Math.sin(ph * 2.01));
    b.add(n0 + j, v, v, send);
  }
}
export function chime(b, at, midi, amp, decay = 1.1, send = 0.55) {
  const f = hz(midi);
  tone(b, at, [[f, 1], [f * 2.0, 0.35], [f * 3.01, 0.12], [f * 4.2, 0.05]], decay * 3, amp, decay, send, 0, 0.002);
}
export function sub(b, at, f, amp, decay) { tone(b, at, [[f, 1], [f * 2, 0.22]], decay * 4, amp, decay, 0.25, 0, 0.02); }
export function click(b, at, amp = 0.1, pan = 0) { tone(b, at, [[2600, 0.4], [880, 1]], 0.07, amp, 0.016, 0.2, pan, 0.002); }

function reverb(inp, N, combs, aps, fb = 0.8, damp = 0.25) {
  const out = new Float32Array(N);
  for (const d of combs) { const buf = new Float32Array(d); let idx = 0, last = 0;
    for (let i = 0; i < N; i++) { const y = buf[idx]; last = y * (1 - damp) + last * damp; buf[idx] = inp[i] + last * fb; idx = (idx + 1) % d; out[i] += y; } }
  for (const d of aps) { const buf = new Float32Array(d); let idx = 0;
    for (let i = 0; i < N; i++) { const bb = buf[idx], x = out[i], y = -x + bb; buf[idx] = x + bb * 0.5; idx = (idx + 1) % d; out[i] = y; } }
  return out;
}
/** Reverb the sends, soft-clip, fade the tail, normalise to `peakDb`, write 16-bit WAV. */
export function render(b, file, { peakDb = -3, wet = 0.09, fadeFrom = null, fadeLen = 0.6 } = {}) {
  const s = SR / 44100, N = b.N;
  const wL = reverb(b.sL, N, [1557, 1617, 1491, 1422].map((d) => Math.round(d * s)), [225, 556].map((d) => Math.round(d * s)));
  const wR = reverb(b.sR, N, [1580, 1640, 1514, 1445].map((d) => Math.round(d * s)), [248, 579].map((d) => Math.round(d * s)));
  const mL = new Float32Array(N), mR = new Float32Array(N); let peak = 1e-9;
  for (let i = 0; i < N; i++) {
    const t = i / SR, fade = fadeFrom != null && t > fadeFrom ? 1 - smooth((t - fadeFrom) / fadeLen) : 1, fin = Math.min(1, t / 0.01);
    mL[i] = Math.tanh((b.L[i] + wL[i] * wet) * 1.1) * fade * fin; mR[i] = Math.tanh((b.R[i] + wR[i] * wet) * 1.1) * fade * fin;
    peak = Math.max(peak, Math.abs(mL[i]), Math.abs(mR[i]));
  }
  const g = Math.pow(10, peakDb / 20) / peak, out = new Int16Array(N * 2); let sq = 0;
  for (let i = 0; i < N; i++) { const l = mL[i] * g, r = mR[i] * g; sq += l * l + r * r; out[i * 2] = Math.round(Math.max(-1, Math.min(1, l)) * 32767); out[i * 2 + 1] = Math.round(Math.max(-1, Math.min(1, r)) * 32767); }
  const h = Buffer.alloc(44), bytes = out.length * 2;
  h.write("RIFF", 0); h.writeUInt32LE(36 + bytes, 4); h.write("WAVE", 8); h.write("fmt ", 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(2, 22);
  h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 4, 28); h.writeUInt16LE(4, 32); h.writeUInt16LE(16, 34); h.write("data", 36); h.writeUInt32LE(bytes, 40);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, Buffer.concat([h, Buffer.from(out.buffer)]));
  return 10 * Math.log10(sq / (N * 2));
}
