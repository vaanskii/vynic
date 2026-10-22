// Fast-motion refine: SFX accents, synced to the cut (colour hits, wipes, item moves, number rolls,
// Manager state changes, the SaaS→Custom transformation). Deliberately not on every click.
//   node audio/sfx.mjs → assets/audio/sfx.wav
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { bus, render, air, glide, chime, sub, click, tone } from "../../audio/lib.mjs";

const DUR = 43.0, b = bus(DUR);
const whoosh = (at, dur, amp = 0.05) => air(b, at, dur, amp, 500, 4200, "hump", 0.2);
const colourHit = (at, amp = 0.16) => { sub(b, at, 48, amp, 0.16); air(b, at - 0.02, 0.22, 0.035, 2400, 600, "hump", 0.2); click(b, at, 0.05); };
const pop = (at, midi, amp = 0.05) => tone(b, at, [[440 * Math.pow(2, (midi - 69) / 12), 1], [880 * Math.pow(2, (midi - 69) / 12), 0.25]], 0.18, amp, 0.045, 0.3, 0, 0.002);
const roll = (at, dur, amp = 0.03) => { for (let t = 0, k = 0; t < dur; k++, t += 0.035 + t * 0.06) click(b, at + t, amp * (1 - t / dur * 0.6), k % 2 ? 0.25 : -0.25); };
const swish = (at, amp = 0.035) => air(b, at, 0.2, amp, 1500, 5200, "draw", 0.15);

// 1 · open
air(b, 0.06, 0.34, 0.035, 1200, 3800, "draw", 0.3);
chime(b, 0.55, 86, 0.05, 0.6); click(b, 0.55, 0.06);
colourHit(1.0, 0.18);
click(b, 1.1, 0.04, 0.2);
air(b, 1.92, 0.6, 0.03, 600, 2600, "rise", 0.3);
colourHit(2.5, 0.12);
// 2 · POS: table tap, items land (rising pops), order added, tab cuts (soft), management
click(b, 3.2, 0.06, -0.2);
pop(4.3, 79); pop(5.12, 83); pop(5.78, 86);
chime(b, 6.55, 81, 0.05, 0.45); chime(b, 6.65, 88, 0.045, 0.6);
click(b, 7.5, 0.035, 0.2);
air(b, 8.2, 0.5, 0.025, 1200, 3600, "hump", 0.2);
[8.6, 9.6, 10.6, 11.6].forEach((t, i) => swish(t, 0.028 + i * 0.003));
air(b, 12.62, 0.45, 0.04, 700, 5200, "rise", 0.2);
// type wipe
whoosh(12.98, 0.36, 0.06); colourHit(13.26, 0.14);
whoosh(13.88, 0.38, 0.055);
// 3 · one system
sub(b, 14.58, 55, 0.12, 0.2); chime(b, 14.6, 81, 0.05, 0.7);
roll(14.88, 0.6);
glide(b, 15.78, 0.35, 700, 1600, 0.018);
whoosh(16.4, 0.55, 0.065); colourHit(16.73, 0.15);
// 4 · Manager: refresh, figures, card out/in, tabs, receiving, cards, save, booking confirmed
air(b, 17.3, 0.4, 0.03, 900, 2600, "draw", 0.2);
roll(17.9, 0.45, 0.025);
swish(18.4, 0.04); roll(18.68, 0.55, 0.025); air(b, 19.87, 0.25, 0.035, 5200, 1500, "draw", 0.15);
swish(20.3, 0.02); swish(21.2, 0.02);
swish(21.95, 0.03);
click(b, 22.55, 0.03, -0.2); click(b, 23.1, 0.03, 0.2); click(b, 23.6, 0.03, -0.2);
swish(24.05, 0.04); roll(24.35, 0.5, 0.025); air(b, 25.37, 0.25, 0.035, 5200, 1500, "draw", 0.15);
chime(b, 25.82, 83, 0.045, 0.45); chime(b, 25.92, 90, 0.04, 0.6);
swish(26.45, 0.02); swish(27.45, 0.02);
chime(b, 28.98, 86, 0.05, 0.5); chime(b, 29.08, 93, 0.04, 0.7);
// scale-through into the web
air(b, 29.95, 0.46, 0.05, 600, 6200, "rise", 0.2); colourHit(30.41, 0.12);
// 5 · web
air(b, 30.95, 1.1, 0.02, 1200, 3000, "hump", 0.2);
click(b, 32.97, 0.04, -0.3); click(b, 33.07, 0.04, 0.3);
air(b, 33.47, 0.3, 0.03, 900, 3000, "draw", 0.3);
glide(b, 33.85, 1.2, 420, 1260, 0.03, 0.5); air(b, 33.85, 1.2, 0.045, 400, 7000, "hump", 0.4);
chime(b, 35.25, 86, 0.05, 0.9); chime(b, 35.33, 93, 0.035, 0.9);
air(b, 36.05, 0.7, 0.02, 1500, 3500, "hump", 0.2);
// 6 · ecosystem
colourHit(37.37, 0.14); whoosh(37.35, 0.5, 0.05);
[37.55, 37.6, 37.65, 37.7].forEach((t, i) => click(b, t, 0.045, i % 2 ? 0.3 : -0.3));
glide(b, 38.2, 0.3, 600, 1800, 0.02);
chime(b, 38.55, 93, 0.035, 0.5);
air(b, 39.53, 0.42, 0.06, 7000, 400, "rise", 0.2);
// 7 · lockup impact
sub(b, 39.95, 45, 0.22, 0.5); air(b, 39.93, 0.5, 0.05, 3000, 500, "hump", 0.4);
chime(b, 40.0, 74, 0.05, 1.6); chime(b, 40.03, 81, 0.045, 1.6); chime(b, 40.07, 90, 0.035, 1.8);
click(b, 40.2, 0.03);

const here = dirname(fileURLToPath(import.meta.url));
const rms = render(b, join(here, "..", "assets/audio/sfx.wav"), { peakDb: -5, wet: 0.12, fadeFrom: 42.3, fadeLen: 0.7 });
console.log(`sfx.wav · ${DUR}s · peak −5.0 dBFS · RMS ${rms.toFixed(1)} dBFS`);
