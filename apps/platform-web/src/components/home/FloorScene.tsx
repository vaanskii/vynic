import { AnimatePresence, motion, useMotionValueEvent, useReducedMotion, useScroll, useSpring, useTransform, type MotionValue } from "motion/react";
import { useRef, useState } from "react";
import screenFloor from "../../assets/screen-pos-floor-live.png";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { Kicker } from "./primitives";
import { getSiteCopy } from "./siteCopy";

// Blocks placed where the real POS floor draws them (fractions of the capture).
type Block = { x: number; y: number; w: number; h: number; label?: string; kind: "table" | "bar" | "stage" | "hot" };
const BLOCKS: Block[] = [
  { x: 0.18, y: 0.255, w: 0.185, h: 0.08, label: "Bar", kind: "bar" },
  { x: 0.212, y: 0.375, w: 0.095, h: 0.075, label: "T2", kind: "table" },
  { x: 0.335, y: 0.375, w: 0.095, h: 0.075, label: "T3", kind: "table" },
  { x: 0.46, y: 0.375, w: 0.095, h: 0.075, label: "T4", kind: "table" },
  { x: 0.212, y: 0.49, w: 0.095, h: 0.085, label: "T1", kind: "hot" },
  { x: 0.548, y: 0.495, w: 0.063, h: 0.17, kind: "stage" },
  { x: 0.185, y: 0.725, w: 0.095, h: 0.075, label: "T5", kind: "table" },
  { x: 0.185, y: 0.865, w: 0.095, h: 0.075, label: "T6", kind: "table" },
  { x: 0.305, y: 0.865, w: 0.095, h: 0.075, label: "T7", kind: "table" },
  { x: 0.425, y: 0.865, w: 0.095, h: 0.075, label: "T8", kind: "table" },
  { x: 0.54, y: 0.865, w: 0.095, h: 0.075, label: "T9", kind: "table" },
];

const TONE: Record<Block["kind"], { top: string; side: string; text: string }> = {
  table: { top: "#f4f1ec", side: "#cfc8bf", text: "#3a342c" },
  bar: { top: "#dbe9f7", side: "#9db8d4", text: "#2b4a6b" },
  stage: { top: "#f6dcea", side: "#d6a6c0", text: "#8a3b62" },
  hot: { top: "#efe2f2", side: "#b48cbb", text: "#4a2f4e" },
};

/**
 * Floor page scene: the room seen in 3D — tables standing up off the floor —
 * straightens into a plan as you scroll, the blocks sink flat, and the real
 * POS floor fades in exactly underneath them.
 */
export function FloorScene() {
  const { locale } = useLocale();
  const copy = getSiteCopy(locale).floorScene;
  const reduce = useReducedMotion();
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end end"] });
  const p = useSpring(scrollYProgress, { stiffness: 90, damping: 24, mass: 0.4 });
  const [step, setStep] = useState(0);
  useMotionValueEvent(scrollYProgress, "change", (value) => {
    const next = value < 0.33 ? 0 : value < 0.68 ? 1 : 2;
    if (next !== step) setStep(next);
  });

  const rotateX = useTransform(p, [0, 0.55], [58, 0]);
  const rotateZ = useTransform(p, [0, 0.55], [-34, 0]);
  const scale = useTransform(p, [0, 0.55, 1], [0.78, 1, 1.02]);
  const lift = useTransform(p, [0.2, 0.62], [42, 0]);
  const real = useTransform(p, [0.66, 0.86], [0, 1]);
  const blocksFade = useTransform(p, [0.7, 0.9], [1, 0]);

  if (reduce) {
    return (
      <section ref={ref} className="px-4 py-16 sm:px-6 lg:px-8">
        <img src={screenFloor} alt="Vynic POS live floor" className="mx-auto w-full max-w-[1100px] rounded-[16px]" />
      </section>
    );
  }

  return (
    <section ref={ref} aria-label={copy.steps.join(" · ")} className="relative h-[340vh]">
      <div className="sticky top-0 flex h-[100dvh] flex-col items-center justify-center overflow-hidden px-4 pt-16">
        <div className="relative z-10 mb-4 flex flex-col items-center text-center sm:mb-8">
          <Kicker>{copy.kicker}</Kicker>
          <div className="relative mt-3 h-[1.15em] w-[92vw] text-[2.4rem] sm:text-5xl lg:text-[4.2rem]">
            <AnimatePresence mode="popLayout" initial={false}>
              <motion.p
                key={step}
                className="vh-display absolute inset-x-0 top-0 text-[var(--vh-text)]"
                initial={{ opacity: 0, y: "70%", rotateX: -70 }}
                animate={{ opacity: 1, y: "0%", rotateX: 0 }}
                exit={{ opacity: 0, y: "-60%", rotateX: 60 }}
                transition={{ duration: 0.7, ease: curve.out }}
                style={{ transformPerspective: 900 }}
              >
                {copy.steps[step]}
              </motion.p>
            </AnimatePresence>
          </div>
        </div>

        <div className="relative w-[min(90vw,1000px,calc((100dvh-280px)*1.547))] [perspective:1800px]">
          <motion.div className="relative aspect-[3456/2234] [transform-style:preserve-3d]" style={{ rotateX, rotateZ, scale }}>
            {/* Floor */}
            <div className="absolute inset-0 rounded-[18px] border border-white/10 bg-[#f6f5f2] shadow-[0_80px_160px_-60px_rgba(0,0,0,0.95)] [background-image:linear-gradient(rgba(28,26,24,0.05)_1px,transparent_1px),linear-gradient(90deg,rgba(28,26,24,0.05)_1px,transparent_1px)] [background-size:3%_4.6%]" />
            <motion.img src={screenFloor} alt="Vynic POS live floor" className="absolute inset-0 h-full w-full rounded-[18px] object-cover" style={{ opacity: real }} draggable={false} />
            <motion.div className="absolute inset-0 [transform-style:preserve-3d]" style={{ opacity: blocksFade }}>
              {BLOCKS.map((block, index) => (
                <Extruded key={index} block={block} lift={lift} />
              ))}
            </motion.div>
          </motion.div>
        </div>

        <div className="mt-8 flex items-center gap-3">
          {copy.steps.map((label, index) => (
            <span key={label} className={`h-1.5 rounded-full transition-all duration-500 ${index === step ? "w-10 bg-[var(--vh-orchid)]" : "w-4 bg-white/20"}`} />
          ))}
        </div>
      </div>
    </section>
  );
}

function Extruded({ block, lift }: { block: Block; lift: MotionValue<number> }) {
  const tone = TONE[block.kind];
  const height = block.kind === "stage" ? 0.6 : block.kind === "bar" ? 1.2 : 1;
  const top = useTransform(lift, (value) => `translateZ(${value * height}px)`);
  const layers = [0.25, 0.5, 0.75];
  return (
    <div
      className="absolute [transform-style:preserve-3d]"
      style={{ left: `${block.x * 100}%`, top: `${block.y * 100}%`, width: `${block.w * 100}%`, height: `${block.h * 100}%` }}
    >
      {layers.map((k) => (
        <Layer key={k} lift={lift} k={k * height} color={tone.side} />
      ))}
      <motion.div
        className="absolute inset-0 flex items-center justify-center rounded-[6px] border border-black/10 text-[clamp(7px,1vw,13px)] font-semibold"
        style={{ transform: top, background: tone.top, color: tone.text, boxShadow: "0 1px 0 rgba(255,255,255,0.6) inset" }}
      >
        {block.label}
      </motion.div>
    </div>
  );
}

function Layer({ lift, k, color }: { lift: MotionValue<number>; k: number; color: string }) {
  const transform = useTransform(lift, (value) => `translateZ(${value * k}px)`);
  return <motion.div className="absolute inset-0 rounded-[6px]" style={{ transform, background: color }} />;
}
