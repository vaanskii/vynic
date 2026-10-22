import { motion, useReducedMotion, useScroll, useTransform } from "motion/react";
import { Fragment, useEffect, useRef, useState, type ElementType, type ReactNode } from "react";
import vynicLogo from "../../assets/vynic-logo.png";
import { curve } from "../../lib/motion";
import type { Accented } from "./homeCopy";

/** Small mono pill with a glowing dot: "• service flow". */
export function Kicker({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <span className={`vh-chip vh-mono inline-flex items-center gap-2 rounded-full px-2.5 py-1 text-[11px] text-[var(--vh-soft)] ${className}`}>
      <span className="vh-kicker-dot h-1.5 w-1.5 rounded-full bg-[var(--vh-orchid)]" />
      {children}
    </span>
  );
}

/**
 * A headline with an italic serif accent. Screen readers get the plain
 * sentence; the visual copy rises word by word when it enters the viewport
 * (or on mount with `immediate`).
 */
export function AccentTitle({
  parts,
  as: Tag = "h2",
  className = "",
  immediate = false,
  delay = 0,
  id,
}: {
  parts: Accented;
  as?: ElementType;
  className?: string;
  immediate?: boolean;
  delay?: number;
  id?: string;
}) {
  const reduce = useReducedMotion();
  const plain = parts.join("").trim();
  const words: Array<{ word: string; accent: boolean }> = [];
  parts.forEach((part, index) => {
    for (const word of part.split(/\s+/).filter(Boolean)) words.push({ word, accent: index === 1 });
  });
  // Punctuation that starts a part ("." / ",") belongs to the previous word.
  const glued = (index: number) => index > 0 && /^[.,;:!?]/.test(words[index].word);

  const container = {
    hidden: {},
    show: { transition: { staggerChildren: 0.045, delayChildren: delay } },
  };
  const item = {
    hidden: { y: "105%" },
    show: { y: "0%", transition: { duration: 0.9, ease: curve.out } },
  };

  return (
    <Tag id={id} className={className}>
      <span className="sr-only">{plain}</span>
      <motion.span
        aria-hidden="true"
        initial={reduce ? false : "hidden"}
        {...(immediate ? { animate: "show" } : { whileInView: "show", viewport: { once: true, amount: 0.6 } })}
        variants={container}
      >
        {words.map(({ word, accent }, index) => (
          <Fragment key={`${word}-${index}`}>
            {index > 0 && !glued(index) ? " " : null}
            <span className="inline-block overflow-hidden pb-[0.12em] -mb-[0.12em] align-top">
              <motion.span className={`inline-block ${accent ? "vh-accent" : ""}`} variants={item}>
                {word}
              </motion.span>
            </span>
          </Fragment>
        ))}
      </motion.span>
    </Tag>
  );
}

/** One-time rise and fade as the block enters the viewport. */
export function Rise({
  children,
  className = "",
  delay = 0,
  y = 22,
  id,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
  y?: number;
  id?: string;
}) {
  const reduce = useReducedMotion();
  return (
    <motion.div
      id={id}
      className={className}
      initial={reduce ? false : { opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, amount: 0.2 }}
      transition={{ duration: 0.8, ease: curve.out, delay }}
    >
      {children}
    </motion.div>
  );
}

/** True once the element has been on screen (stays true). */
export function useSeen<T extends Element>(amount = 0.35) {
  const ref = useRef<T>(null);
  // Without IntersectionObserver (old browsers, tests) everything counts as seen.
  const [seen, setSeen] = useState(() => typeof IntersectionObserver === "undefined");
  useEffect(() => {
    const element = ref.current;
    if (!element || seen) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setSeen(true);
          observer.disconnect();
        }
      },
      { threshold: amount },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, [amount, seen]);
  return [ref, seen] as const;
}

/** True while the element is on screen — for loops that should pause off-screen. */
export function useOnScreen<T extends Element>() {
  const ref = useRef<T>(null);
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const element = ref.current;
    if (!element || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting), { threshold: 0.1 });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return [ref, visible] as const;
}

/** Counts from 0 to `value` once `run` turns true. */
export function CountUp({
  value,
  run,
  decimals = 0,
  duration = 1.4,
  format = (n: number) => n.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals }),
}: {
  value: number;
  run: boolean;
  decimals?: number;
  duration?: number;
  format?: (n: number) => string;
}) {
  const reduce = useReducedMotion();
  const [shown, setShown] = useState(0);
  useEffect(() => {
    if (!run || reduce) return;
    let frame = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / (duration * 1000));
      const eased = 1 - Math.pow(1 - t, 4);
      setShown(value * eased);
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [run, value, duration, reduce]);
  return <>{format(reduce ? value : shown)}</>;
}

/**
 * The reference layout for a section opening: kicker and accented title on
 * the left, a short paragraph on the right.
 */
export function SectionOpen({
  kicker,
  title,
  body,
  id,
  aside,
}: {
  kicker: string;
  title: Accented;
  body?: string;
  id?: string;
  aside?: ReactNode;
}) {
  return (
    <div className="grid grid-cols-[minmax(0,1fr)] gap-6 lg:grid-cols-[1.2fr_0.8fr] lg:items-end">
      <div>
        <Rise>
          <Kicker>{kicker}</Kicker>
        </Rise>
        <AccentTitle
          id={id}
          parts={title}
          className="vh-display mt-5 max-w-[18ch] text-[2.6rem] text-[var(--vh-text)] sm:text-6xl lg:text-[4.5rem]"
        />
      </div>
      {body || aside ? (
        <Rise delay={0.12} className="lg:justify-self-end">
          {body ? <p className="max-w-md text-[15px] leading-7 text-[var(--vh-muted)]">{body}</p> : null}
          {aside}
        </Rise>
      ) : null}
    </div>
  );
}

/** The Vynic mark on its own light tile, so the dark "V" reads on charcoal. */
export function BrandMark({ size = 32, className = "" }: { size?: number; className?: string }) {
  return (
    <span
      className={`inline-flex shrink-0 items-center justify-center bg-[#f2edf7] shadow-[0_0_0_1px_rgba(247,246,244,0.12)] ${className}`}
      style={{ width: size, height: size, borderRadius: size * 0.28, padding: size * 0.16 }}
    >
      <img src={vynicLogo} alt="" className="h-full w-full object-contain" />
    </span>
  );
}

/** Scroll parallax: the block drifts from +amount to −amount px as it crosses the viewport. */
export function Drift({ children, amount = 50, className = "" }: { children: ReactNode; amount?: number; className?: string }) {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start end", "end start"] });
  const y = useTransform(scrollYProgress, [0, 1], [amount, -amount]);
  return (
    <motion.div ref={ref} className={className} style={reduce ? undefined : { y }}>
      {children}
    </motion.div>
  );
}
