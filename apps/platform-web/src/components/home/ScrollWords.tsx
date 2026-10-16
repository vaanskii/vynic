import { motion, useAnimationFrame, useMotionValue, useReducedMotion, useScroll, useSpring, useTransform, useVelocity, type MotionValue } from "motion/react";
import { useRef } from "react";
import { useLocale } from "../../lib/i18n";
import { getHomeCopy } from "./homeCopy";
import { Kicker } from "./primitives";

/** A long sentence whose words light up one by one as it scrolls through. */
export function ScrollWords() {
  const { locale } = useLocale();
  const copy = getHomeCopy(locale).words;
  const reduce = useReducedMotion();
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start 85%", "end 45%"] });
  const words = copy.text.split(/\s+/);

  return (
    <section aria-label={copy.text} className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-36">
      <div ref={ref} className="mx-auto max-w-[1100px]">
        <Kicker>{copy.kicker}</Kicker>
        <p aria-hidden="true" className="vh-display mt-8 text-[2.3rem] !leading-[1.05] text-[var(--vh-text)] sm:text-6xl lg:text-[4.6rem]">
          {words.map((word, index) => (
            <Word key={`${word}-${index}`} progress={scrollYProgress} start={index / words.length} end={(index + 1) / words.length} still={Boolean(reduce)}>
              {word}
            </Word>
          ))}
        </p>
      </div>
    </section>
  );
}

function Word({ children, progress, start, end, still }: { children: string; progress: MotionValue<number>; start: number; end: number; still: boolean }) {
  const opacity = useTransform(progress, [start, end], [0.14, 1]);
  const y = useTransform(progress, [start, end], [8, 0]);
  const lit = useTransform(progress, (value) => (value >= end ? "#f7f6f4" : value >= start ? "#d8b6de" : "#f7f6f4"));
  return (
    <>
      <motion.span className="inline-block" style={still ? undefined : { opacity, y, color: lit }}>
        {children}
      </motion.span>{" "}
    </>
  );
}

/**
 * A slow band of Vynic's local details. It drifts on its own and leans into
 * the direction (and speed) of the visitor's scroll.
 */
export function ScrollMarquee() {
  const { locale } = useLocale();
  const items = getHomeCopy(locale).words.marquee;
  const reduce = useReducedMotion();
  const base = useMotionValue(0);
  const { scrollY } = useScroll();
  const velocity = useSpring(useVelocity(scrollY), { damping: 50, stiffness: 300 });
  const boost = useTransform(velocity, [-2000, 0, 2000], [-4, 0, 4], { clamp: false });
  const direction = useRef(1);

  useAnimationFrame((_, delta) => {
    if (reduce) return;
    const push = boost.get();
    if (push < -0.01) direction.current = -1;
    else if (push > 0.01) direction.current = 1;
    const move = direction.current * 2.2 * (delta / 1000) * (1 + Math.abs(push));
    // Wrap within one copy of the track (a quarter of the 4× content).
    base.set((((base.get() - move) % 25) - 25) % 25);
  });
  const x = useTransform(base, (value) => `${value}%`);
  const track = [...items, ...items, ...items, ...items];

  return (
    <div aria-hidden="true" className="relative overflow-hidden border-y border-[var(--vh-line)] bg-black/20 py-5">
      <motion.div className="flex w-max gap-10 whitespace-nowrap" style={{ x }}>
        {track.map((item, index) => (
          <span key={`${item}-${index}`} className="vh-display flex items-center gap-10 text-[2rem] text-[var(--vh-text)]/80 sm:text-[2.6rem]">
            {item}
            <span className="h-2 w-2 rounded-full bg-[var(--vh-orchid)] shadow-[0_0_12px_rgba(216,182,222,0.8)]" />
          </span>
        ))}
      </motion.div>
    </div>
  );
}
