import { ArrowRight } from "@phosphor-icons/react";
import { motion, useReducedMotion, useScroll, useTransform, type MotionValue } from "motion/react";
import { Fragment, useRef, type CSSProperties, type ElementType, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { curve } from "../../lib/motion";
import type { Accented } from "./homeCopy";
import { Kicker } from "./primitives";

/**
 * Kinetic headline: every letter flips up out of the baseline in 3D, one after
 * another. Words never break inside; screen readers get the plain sentence.
 */
export function KineticTitle({
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
  const letters = words.reduce((sum, { word }) => sum + Array.from(word).length, 0);
  const step = Math.min(0.028, 0.9 / Math.max(1, letters));
  let index = 0;

  const container = { hidden: {}, show: { transition: { staggerChildren: step, delayChildren: delay } } };
  const letter = {
    hidden: { y: "0.9em", rotateX: -95, opacity: 0 },
    show: { y: "0em", rotateX: 0, opacity: 1, transition: { duration: 0.9, ease: curve.out } },
  };

  return (
    <Tag id={id} className={className}>
      <span className="sr-only">{plain}</span>
      <motion.span
        aria-hidden="true"
        className="[perspective:900px]"
        initial={reduce ? false : "hidden"}
        {...(immediate ? { animate: "show" } : { whileInView: "show", viewport: { once: true, amount: 0.5 } })}
        variants={container}
      >
        {words.map(({ word, accent }, wordIndex) => (
          <Fragment key={`${word}-${wordIndex}`}>
            {wordIndex > 0 && !/^[.,;:!?]/.test(word) ? " " : null}
            <span className={`inline-block whitespace-nowrap [transform-style:preserve-3d] ${accent ? "vh-accent" : ""}`}>
              {Array.from(word).map((char) => {
                index += 1;
                return (
                  <motion.span key={index} className="inline-block origin-[50%_100%] [backface-visibility:hidden]" variants={letter}>
                    {char}
                  </motion.span>
                );
              })}
            </span>
          </Fragment>
        ))}
      </motion.span>
    </Tag>
  );
}

/**
 * A page opening: kicker, kinetic title, body and a visual. On scroll the
 * title drifts up and loosens while the visual leans back into depth.
 */
export function PageHero({ kicker, title, body, visual, aside }: { kicker: string; title: Accented; body: string; visual?: ReactNode; aside?: ReactNode }) {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end start"] });
  const titleY = useTransform(scrollYProgress, [0, 1], [0, -140]);
  const spacing = useTransform(scrollYProgress, [0, 1], ["-0.015em", "0.06em"]);
  const fade = useTransform(scrollYProgress, [0, 0.75], [1, 0]);
  const visualRotate = useTransform(scrollYProgress, [0, 1], [0, 24]);
  const visualScale = useTransform(scrollYProgress, [0, 1], [1, 0.86]);
  const visualY = useTransform(scrollYProgress, [0, 1], [0, 120]);

  return (
    <section ref={ref} className="relative overflow-x-clip px-4 pb-16 pt-14 sm:px-6 lg:px-8 lg:pb-24 lg:pt-20">
      <div className="mx-auto max-w-[1320px]">
        <motion.div style={reduce ? undefined : { y: titleY, opacity: fade }}>
          <motion.div initial={reduce ? false : { opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.7, ease: curve.out }}>
            <Kicker>{kicker}</Kicker>
          </motion.div>
          <motion.div style={reduce ? undefined : { letterSpacing: spacing }}>
            <KineticTitle
              as="h1"
              immediate
              delay={0.15}
              parts={title}
              className="vh-display mt-6 max-w-[16ch] text-[3rem] text-[var(--vh-text)] sm:text-7xl lg:text-[7.2rem]"
            />
          </motion.div>
          <div className="mt-8 grid grid-cols-[minmax(0,1fr)] gap-6 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
            <motion.p
              className="max-w-[52ch] text-[15px] leading-7 text-[var(--vh-muted)] sm:text-base"
              initial={reduce ? false : { opacity: 0, y: 14 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, ease: curve.out, delay: 0.6 }}
            >
              {body}
            </motion.p>
            {aside}
          </div>
        </motion.div>
        {visual ? (
          <div className="mt-14 [perspective:1600px] lg:mt-20">
            <motion.div
              style={reduce ? undefined : { rotateX: visualRotate, scale: visualScale, y: visualY, transformOrigin: "50% 0%" }}
              initial={reduce ? false : { opacity: 0, y: 80, rotateX: 30 }}
              animate={{ opacity: 1, y: 0, rotateX: 0 }}
              transition={{ duration: 1.4, ease: curve.out, delay: 0.35 }}
            >
              {visual}
            </motion.div>
          </div>
        ) : null}
      </div>
    </section>
  );
}

/**
 * A tablet with real thickness: the bezel is extruded in stacked layers so it
 * keeps its depth when the scene rotates it in 3D.
 */
export function Tablet({
  children,
  rotateX,
  rotateY,
  rotateZ,
  className = "",
  style,
}: {
  children: ReactNode;
  rotateX?: MotionValue<number> | number;
  rotateY?: MotionValue<number> | number;
  rotateZ?: MotionValue<number> | number;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <motion.div className={`relative [transform-style:preserve-3d] ${className}`} style={{ rotateX, rotateY, rotateZ, ...style }}>
      {/* Extruded body */}
      {Array.from({ length: 10 }, (_, layer) => (
        <div
          key={layer}
          aria-hidden="true"
          className="absolute inset-0 rounded-[26px]"
          style={{ transform: `translateZ(${-(layer + 1) * 1.6}px)`, background: layer === 9 ? "#0b0a09" : `rgb(${46 - layer * 2},${43 - layer * 2},${41 - layer * 2})` }}
        />
      ))}
      <div className="relative rounded-[26px] border border-white/10 bg-[#1a1816] p-[1.6%] shadow-[0_80px_140px_-50px_rgba(0,0,0,0.95)]">
        <div className="relative overflow-hidden rounded-[16px] bg-[#f6f5f2]">{children}</div>
      </div>
    </motion.div>
  );
}

/** The closing hand-off on every page: a huge link to the next part of the platform. */
export function NextPage({ label, title, to }: { label: string; title: string; to: string }) {
  const reduce = useReducedMotion();
  return (
    <section className="relative px-4 pb-10 pt-24 sm:px-6 lg:px-8 lg:pt-32">
      <Link to={to} className="group mx-auto block max-w-[1320px] border-t border-[var(--vh-line-strong)] pt-8">
        <span className="vh-mono flex items-center gap-2 text-[11px] text-[var(--vh-faint)]">
          {label}
          <span className="h-px w-10 bg-[var(--vh-faint)] transition-all duration-500 group-hover:w-20 group-hover:bg-[var(--vh-orchid)]" />
        </span>
        <span className="mt-4 flex items-end justify-between gap-6">
          <motion.span
            className="vh-display block text-[3.4rem] text-[var(--vh-text)] transition-colors duration-500 group-hover:text-[var(--vh-orchid)] sm:text-8xl lg:text-[10rem]"
            initial={reduce ? false : { opacity: 0, x: -40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true, amount: 0.6 }}
            transition={{ duration: 1, ease: curve.out }}
          >
            {title}
          </motion.span>
          <span className="vh-btn-primary mb-3 flex h-14 w-14 shrink-0 items-center justify-center rounded-full text-white transition-transform duration-500 group-hover:-rotate-45 group-hover:scale-110 sm:h-20 sm:w-20">
            <ArrowRight size={26} weight="bold" />
          </span>
        </span>
      </Link>
    </section>
  );
}
