import { useEffect, useRef } from "react";

/**
 * The homepage backdrop: bundles of fine light strands in Vynic plum, lilac
 * and sage that fold into a bright knot behind the hero and unwind into slow
 * diagonal sweeps further down the page. One fixed canvas, additive blending,
 * no images. The shape follows page scroll; time adds a gentle drift.
 *
 * Reduced motion draws the same field without drift (it still follows scroll
 * so sections keep their composition). Hidden tabs stop drawing.
 */

type Scene = {
  /** Fold vertex as a fraction of the viewport. */
  vx: number;
  vy: number;
  /** How wide the folded strands open (fraction of viewport width). */
  open: number;
  /** Vertical reach of each strand (fraction of viewport height). */
  reach: number;
  /** Rotation of the whole bundle, radians. */
  tilt: number;
  /** Spread between neighbouring strands. */
  spread: number;
  /** Overall brightness. */
  glow: number;
};

// Page progress 0 → 1. Hero knot, then sweeps that drift across the page.
const SCENES: Array<[number, Scene]> = [
  [0, { vx: 0.43, vy: 0.64, open: 0.95, reach: 0.95, tilt: -0.18, spread: 1, glow: 1 }],
  [0.1, { vx: 0.2, vy: 0.4, open: 1.4, reach: 1.25, tilt: 0.5, spread: 1.35, glow: 0.8 }],
  [0.28, { vx: -0.2, vy: 0.48, open: 1.8, reach: 1.1, tilt: 0.95, spread: 1.7, glow: 0.42 }],
  [0.46, { vx: 1.1, vy: 0.3, open: 1.6, reach: 1.3, tilt: -0.75, spread: 1.6, glow: 0.4 }],
  [0.66, { vx: 0.5, vy: -0.25, open: 1.7, reach: 1.4, tilt: 1.45, spread: 1.4, glow: 0.48 }],
  [0.86, { vx: 0.25, vy: 0.2, open: 1.5, reach: 1.2, tilt: 0.25, spread: 1.2, glow: 0.62 }],
  [1, { vx: 0.6, vy: 0.75, open: 1.1, reach: 1.1, tilt: -0.3, spread: 1, glow: 0.75 }],
];

const STRANDS = 44;
const SEGMENTS = 70;
const PARTICLES = 70;

// Vynic tones (r, g, b), lifted for light-on-dark: lilac, orchid, plum, sage.
const TONES: Array<[number, number, number]> = [
  [176, 132, 206],
  [222, 150, 232],
  [168, 92, 182],
  [150, 204, 158],
];

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}

function smooth(t: number) {
  return t * t * (3 - 2 * t);
}

function sceneAt(progress: number): Scene {
  for (let index = 1; index < SCENES.length; index += 1) {
    const [end, to] = SCENES[index];
    const [start, from] = SCENES[index - 1];
    if (progress <= end) {
      const t = smooth((progress - start) / (end - start || 1));
      return {
        vx: lerp(from.vx, to.vx, t),
        vy: lerp(from.vy, to.vy, t),
        open: lerp(from.open, to.open, t),
        reach: lerp(from.reach, to.reach, t),
        tilt: lerp(from.tilt, to.tilt, t),
        spread: lerp(from.spread, to.spread, t),
        glow: lerp(from.glow, to.glow, t),
      };
    }
  }
  return SCENES[SCENES.length - 1][1];
}

type Strand = { offset: number; tone: [number, number, number]; phase: number; weight: number; alpha: number };

function makeStrands(): Strand[] {
  return Array.from({ length: STRANDS }, (_, index) => {
    const centred = index / (STRANDS - 1) - 0.5;
    // Mostly lilac/orchid, a plum core, a few sage strands for depth.
    const pick = index % 11 === 3 || index % 13 === 7 ? 3 : index % 5 === 0 ? 2 : index % 2;
    return {
      offset: centred,
      tone: TONES[pick],
      phase: (index * 0.618) % 1,
      weight: pick === 2 ? 1.25 : 0.8 + ((index * 37) % 10) / 25,
      alpha: 0.45 + ((index * 53) % 10) / 20,
    };
  });
}

export function RibbonField() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    // jsdom has no canvas; skip quietly in tests.
    if (!canvas || /jsdom/i.test(navigator.userAgent)) return;
    const context = canvas.getContext("2d");
    if (!context) return;

    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    const strands = makeStrands();
    const particles = Array.from({ length: PARTICLES }, (_, index) => ({
      strand: (index * 7) % STRANDS,
      at: ((index * 0.137) % 1) * 2 - 1,
      speed: 0.02 + ((index * 29) % 10) / 400,
      size: 0.6 + ((index * 17) % 10) / 9,
    }));

    let width = 0;
    let height = 0;
    let frame = 0;
    let running = true;
    let progress = 0;
    let shown = 0;
    const start = performance.now();

    const resize = () => {
      const ratio = Math.min(window.devicePixelRatio || 1, 1.5);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
    };

    const readScroll = () => {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      progress = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
    };

    const point = (scene: Scene, strand: Strand, s: number, time: number) => {
      // A sideways fold: every strand is a parabola opening to the right,
      // nested around one vertex, so they bunch into a bright knot there.
      const spread = strand.offset * scene.spread;
      const curvature = scene.open * width * (0.55 + spread * 0.9);
      const drift = reduce ? 0 : Math.sin(time * 0.35 + strand.phase * 6.28 + s * 2.4) * 18;
      const ripple = reduce ? 0 : Math.sin(time * 0.22 + s * 4 + strand.phase * 3) * 10;
      const localX = curvature * s * s + spread * 120 + ripple;
      const localY = s * height * 0.62 * scene.reach + spread * 70 + drift;
      const cos = Math.cos(scene.tilt);
      const sin = Math.sin(scene.tilt);
      return [scene.vx * width + localX * cos - localY * sin, scene.vy * height + localX * sin + localY * cos];
    };

    const draw = (now: number) => {
      const time = (now - start) / 1000;
      // Ease toward scroll so fast flicks still glide.
      shown += (progress - shown) * (reduce ? 1 : 0.08);
      const scene = sceneAt(shown);
      context.clearRect(0, 0, width, height);
      context.globalCompositeOperation = "lighter";
      context.lineCap = "round";

      for (const strand of strands) {
        const [r, g, b] = strand.tone;
        const path = new Path2D();
        for (let step = 0; step <= SEGMENTS; step += 1) {
          const s = (step / SEGMENTS) * 2 - 1;
          const [x, y] = point(scene, strand, s, time);
          if (step === 0) path.moveTo(x, y);
          else path.lineTo(x, y);
        }
        // Soft halo, then the thin bright core.
        const centreFade = 1 - Math.min(1, Math.abs(strand.offset) * 1.6);
        const base = scene.glow * strand.alpha * (0.35 + centreFade * 0.65);
        context.strokeStyle = `rgba(${r},${g},${b},${0.06 * base})`;
        context.lineWidth = 7 * strand.weight;
        context.stroke(path);
        context.strokeStyle = `rgba(${r},${g},${b},${0.55 * base})`;
        context.lineWidth = 1.05 * strand.weight;
        context.stroke(path);
      }

      // The knot: a warm bloom where the strands meet.
      const [kx, ky] = point(scene, strands[Math.floor(STRANDS / 2)], 0, time);
      const bloom = context.createRadialGradient(kx, ky, 0, kx, ky, Math.max(width, height) * 0.22);
      bloom.addColorStop(0, `rgba(240,214,246,${0.22 * scene.glow})`);
      bloom.addColorStop(0.25, `rgba(168,92,182,${0.12 * scene.glow})`);
      bloom.addColorStop(1, "rgba(0,0,0,0)");
      context.fillStyle = bloom;
      context.fillRect(0, 0, width, height);

      // Dust riding the strands.
      for (const particle of particles) {
        if (!reduce) {
          particle.at += particle.speed * 0.016;
          if (particle.at > 1) particle.at = -1;
        }
        const strand = strands[particle.strand];
        const [x, y] = point(scene, strand, particle.at, time);
        const [r, g, b] = strand.tone;
        context.fillStyle = `rgba(${r},${g},${b},${0.55 * scene.glow})`;
        context.beginPath();
        context.arc(x, y, particle.size, 0, Math.PI * 2);
        context.fill();
      }
      context.globalCompositeOperation = "source-over";
    };

    const loop = (now: number) => {
      if (!running) return;
      draw(now);
      frame = window.requestAnimationFrame(loop);
    };

    const onVisibility = () => {
      if (document.visibilityState === "hidden") {
        running = false;
        window.cancelAnimationFrame(frame);
      } else if (!reduce && !running) {
        running = true;
        frame = window.requestAnimationFrame(loop);
      }
    };

    const onScroll = () => {
      readScroll();
      if (reduce) draw(performance.now());
    };

    resize();
    readScroll();
    shown = progress;
    if (reduce) {
      running = false;
      draw(start);
    } else {
      frame = window.requestAnimationFrame(loop);
    }

    const onResize = () => {
      resize();
      readScroll();
      if (reduce) draw(performance.now());
    };
    window.addEventListener("resize", onResize);
    window.addEventListener("scroll", onScroll, { passive: true });
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      running = false;
      window.cancelAnimationFrame(frame);
      window.removeEventListener("resize", onResize);
      window.removeEventListener("scroll", onScroll);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return (
    <div className="vh-backdrop" aria-hidden="true">
      <canvas ref={canvasRef} />
    </div>
  );
}
