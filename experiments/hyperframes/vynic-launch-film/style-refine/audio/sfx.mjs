// Fast-motion refine: SFX accents, synced to the cut (colour hits, wipes, item moves, number rolls,
// Manager state changes, the SaaS→Custom transformation). Deliberately not on every click.
//   node audio/sfx.mjs → assets/audio/sfx.wav
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { bus, render, air, glide, chime, sub, click, tone } from "../../audio/lib.mjs";

const DUR = 32.2, b = bus(DUR);
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
// 2 · POS: tap, panel, item moves (rising pops), confirm, push
click(b, 3.2, 0.06, -0.2);
swish(3.34, 0.025);
pop(3.93, 79); pop(4.38, 83); pop(4.83, 86);
chime(b, 5.47, 81, 0.05, 0.45); chime(b, 5.57, 88, 0.045, 0.6);
air(b, 6.35, 0.6, 0.04, 700, 5200, "rise", 0.2);
// type wipe
whoosh(6.7, 0.36, 0.06); colourHit(6.98, 0.14);
whoosh(7.6, 0.38, 0.055);
// 3 · one system: dock, number roll, line zips
sub(b, 8.3, 55, 0.12, 0.2); chime(b, 8.32, 81, 0.05, 0.7);
roll(8.6, 0.6);
glide(b, 9.5, 0.35, 700, 1600, 0.018);
// whip + signal hit
whoosh(10.12, 0.55, 0.065); colourHit(10.45, 0.15);
// 4 · Manager
roll(11.2, 0.5, 0.025);
swish(11.75, 0.04); roll(12.05, 0.55, 0.025); air(b, 13.27, 0.25, 0.035, 5200, 1500, "draw", 0.15);
swish(14.1, 0.02);
swish(14.85, 0.03);
swish(15.45, 0.04); roll(15.75, 0.5, 0.025); air(b, 16.97, 0.25, 0.035, 5200, 1500, "draw", 0.15);
chime(b, 17.47, 83, 0.045, 0.45); chime(b, 17.57, 90, 0.04, 0.6);
// scale-through into the web
air(b, 19.2, 0.46, 0.05, 600, 6200, "rise", 0.2); colourHit(19.66, 0.12);
// 5 · web: scroll, anchor, lift, the transformation sweep, settle
air(b, 20.2, 1.1, 0.02, 1200, 3000, "hump", 0.2);
click(b, 22.22, 0.04, -0.3); click(b, 22.32, 0.04, 0.3);
air(b, 22.72, 0.3, 0.03, 900, 3000, "draw", 0.3);
glide(b, 23.1, 1.2, 420, 1260, 0.03, 0.5); air(b, 23.1, 1.2, 0.045, 400, 7000, "hump", 0.4);
chime(b, 24.5, 86, 0.05, 0.9); chime(b, 24.58, 93, 0.035, 0.9);
air(b, 25.3, 0.7, 0.02, 1500, 3500, "hump", 0.2);
// 6 · ecosystem: ink hit, assemble ticks, zips, pulse, implode
colourHit(26.62, 0.14); whoosh(26.6, 0.5, 0.05);
[26.8, 26.85, 26.9, 26.95].forEach((t, i) => click(b, t, 0.045, i % 2 ? 0.3 : -0.3));
glide(b, 27.45, 0.3, 600, 1800, 0.02);
chime(b, 27.8, 93, 0.035, 0.5);
air(b, 28.78, 0.42, 0.06, 7000, 400, "rise", 0.2);
// 7 · lockup impact
sub(b, 29.2, 45, 0.22, 0.5); air(b, 29.18, 0.5, 0.05, 3000, 500, "hump", 0.4);
chime(b, 29.25, 74, 0.05, 1.6); chime(b, 29.28, 81, 0.045, 1.6); chime(b, 29.32, 90, 0.035, 1.8);
click(b, 29.45, 0.03);

const here = dirname(fileURLToPath(import.meta.url));
const rms = render(b, join(here, "..", "assets/audio/sfx.wav"), { peakDb: -5, wet: 0.12, fadeFrom: 31.5, fadeLen: 0.7 });
console.log(`sfx.wav · ${DUR}s · peak −5.0 dBFS · RMS ${rms.toFixed(1)} dBFS`);
