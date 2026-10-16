// Vynic launch film: sound design stem (original, synthesised). Only the moments that matter.
//   node audio/sfx.mjs  → assets/audio/sfx.wav
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { bus, render, hz, tone, air, glide, chime, sub, click } from "./lib.mjs";

const b = bus(60.0);
const move = (at, dur, amp = 0.05) => { air(b, at, dur, amp, 110, 1300, "hump", 0.35); glide(b, at + dur * 0.15, dur * 0.8, 55, 82, amp * 0.8, 0.2); };

// 1 · the mark (atmospheric)
chime(b, 0.2, 93, 0.03, 1.4);                          // spark
air(b, 0.45, 0.8, 0.035, 700, 4200, "draw");           // thick stroke
air(b, 0.95, 0.7, 0.028, 1100, 5200, "draw");          // thin stroke
air(b, 1.25, 1.0, 0.028, 180, 1600);                   // wordmark with depth
sub(b, 1.3, 49, 0.09, 0.45);
glide(b, 1.65, 0.75, 1400, 2800, 0.008, 0.7);          // light through the mark
chime(b, 1.7, 86, 0.016, 1.6);
move(4.4, 1.6, 0.045);                       // camera leaves the mark
glide(b, 4.45, 1.1, 700, 1050, 0.007, 0.6);            // the stroke traces the terminal
// 2 · POS
click(b, 7.6, 0.06, -0.1);                             // table select (soft)
tone(b, 11.25, [[hz(76), 1], [hz(88), 0.25]], 0.5, 0.04, 0.12, 0.45);   // order confirmed …
tone(b, 11.4, [[hz(81), 1], [hz(93), 0.2]], 0.9, 0.04, 0.22, 0.5);      // … sent to the kitchen
move(13.2, 2.2, 0.035);                                // step back to the terminal
// 3 · data connection
glide(b, 18.7, 1.35, 330, 660, 0.014);                 // capsule into the V
chime(b, 20.1, 88, 0.035, 1.3); chime(b, 20.105, 83, 0.02, 1.4); sub(b, 20.1, 47, 0.06, 0.3);
glide(b, 21.5, 0.8, 500, 1000, 0.009);                 // menu pulse
// handoff to Manager: one restrained transition
air(b, 22.6, 1.7, 0.04, 120, 1500, "hump", 0.35); glide(b, 22.5, 1.7, 440, 880, 0.011); sub(b, 24.15, 52, 0.06, 0.3);
// 4 · Manager
chime(b, 25.3, 83, 0.028, 1.1);                        // figures land after refresh
air(b, 29.75, 0.6, 0.018, 500, 2600);                  // tab change (barely there)
tone(b, 33.3, [[hz(69), 1], [hz(76), 0.5]], 0.7, 0.04, 0.16, 0.4);      // Inventory cue: receiving confirmed
chime(b, 33.95, 81, 0.018, 1.2);
// 5 · websites
move(38.6, 1.7, 0.04);
glide(b, 39.2, 0.8, 500, 1000, 0.01);
air(b, 46.5, 0.6, 0.02, 400, 2400);                    // the dish lifts
air(b, 47.0, 2.0, 0.045, 300, 4800, "hump", 0.55);     // SaaS → Custom
chime(b, 49.0, 79, 0.026, 1.6);                        // it settles into the bespoke menu
// 6 · ecosystem, 7 · lockup
move(52.7, 1.5, 0.045);
glide(b, 54.3, 0.8, 600, 1200, 0.011);
air(b, 56.6, 0.8, 0.05, 300, 3400, "rise", 0.3);       // fold inward
sub(b, 57.6, 55, 0.18, 0.6);                           // restrained lockup impact (A1)
chime(b, 57.6, 74, 0.035, 1.7); chime(b, 57.61, 81, 0.026, 1.7); chime(b, 57.62, 90, 0.016, 1.5);

const here = dirname(fileURLToPath(import.meta.url));
const rms = render(b, join(here, "..", "assets/audio/sfx.wav"), { peakDb: -6, wet: 0.12, fadeFrom: 59.4, fadeLen: 0.6 });
console.log(`sfx.wav · 60s · peak −6.0 dBFS · RMS ${rms.toFixed(1)} dBFS`);
