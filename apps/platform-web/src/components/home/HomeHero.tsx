import { ArrowRight, Play } from "@phosphor-icons/react";
import { motion, useMotionValue, useReducedMotion, useScroll, useSpring, useTransform } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { hasCustomerSession } from "../../customer/api";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy, type Accented } from "./homeCopy";
import { LiveServicePanel } from "./LiveServicePanel";
import { AccentTitle, Kicker } from "./primitives";

function splitAccent(title: string, accent: string): Accented {
  const at = title.indexOf(accent);
  if (at < 0) return [title, "", ""];
  return [title.slice(0, at), accent, title.slice(at + accent.length)];
}

export function HomeHero() {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale);
  const reduce = useReducedMotion();
  const sectionRef = useRef<HTMLElement>(null);
  const signedIn = hasCustomerSession();
  // The 3D lean is a wide-screen effect; small screens keep the panel flat.
  const [wide] = useState(() => window.matchMedia?.("(min-width: 1024px)").matches ?? false);

  // Pointer depth: the panel leans toward the cursor (fine pointers only).
  const px = useMotionValue(0);
  const py = useMotionValue(0);
  const rotateY = useSpring(useTransform(px, [-1, 1], [-9, -2]), { stiffness: 60, damping: 18 });
  const rotateX = useSpring(useTransform(py, [-1, 1], [5, 1]), { stiffness: 60, damping: 18 });
  const frontX = useSpring(useTransform(px, [-1, 1], [-14, 14]), { stiffness: 60, damping: 18 });
  const frontY = useSpring(useTransform(py, [-1, 1], [-10, 10]), { stiffness: 60, damping: 18 });

  useEffect(() => {
    const section = sectionRef.current;
    if (!section || reduce) return;
    if (!window.matchMedia?.("(min-width: 1024px) and (hover: hover) and (pointer: fine)").matches) return;
    const move = (event: PointerEvent) => {
      const box = section.getBoundingClientRect();
      px.set(((event.clientX - box.left) / box.width) * 2 - 1);
      py.set(((event.clientY - box.top) / box.height) * 2 - 1);
    };
    section.addEventListener("pointermove", move);
    return () => section.removeEventListener("pointermove", move);
  }, [px, py, reduce]);

  // Leaving the hero: the panel recedes, the copy yields.
  const { scrollYProgress } = useScroll({ target: sectionRef, offset: ["start start", "end start"] });
  const panelY = useTransform(scrollYProgress, [0, 1], [0, 120]);
  const panelScale = useTransform(scrollYProgress, [0, 1], [1, 0.92]);
  const copyY = useTransform(scrollYProgress, [0, 1], [0, -60]);
  const copyFade = useTransform(scrollYProgress, [0, 0.8], [1, 0.2]);

  const enter = (delay: number) =>
    reduce
      ? {}
      : {
          initial: { opacity: 0, y: 18, filter: "blur(6px)" },
          animate: { opacity: 1, y: 0, filter: "blur(0px)" },
          transition: { duration: 0.9, ease: curve.out, delay },
        };

  return (
    <section ref={sectionRef} id="top" className="relative">
      <div className="mx-auto grid grid-cols-[minmax(0,1fr)] min-h-[calc(100dvh-64px)] max-w-[1320px] items-center gap-14 px-4 pb-24 pt-10 sm:px-6 lg:grid-cols-[0.92fr_1.08fr] lg:gap-10 lg:px-8 lg:pb-16">
        <motion.div style={reduce ? undefined : { y: copyY, opacity: copyFade }}>
          <motion.div {...enter(0.05)}>
            <Kicker>{home.hero.pill}</Kicker>
          </motion.div>
          <AccentTitle
            as="h1"
            immediate
            delay={0.12}
            parts={splitAccent(copy.hero.title, home.hero.accent)}
            className={`vh-display mt-6 text-[var(--vh-text)] ${
              locale === "ka" ? "max-w-[14ch] text-[2.7rem] sm:text-6xl lg:text-[4.7rem]" : "max-w-[11ch] text-[3.5rem] sm:text-7xl lg:text-[6.4rem]"
            }`}
          />
          <motion.p {...enter(0.35)} className="mt-6 max-w-[46ch] text-[15px] leading-7 text-[var(--vh-muted)] sm:text-base">
            {copy.hero.body}
          </motion.p>
          <motion.div {...enter(0.45)} className="mt-8 flex flex-wrap items-center gap-3">
            <Link
              to={signedIn ? "/dashboard" : "/request-access"}
              className="vh-btn-primary group inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold text-white transition-transform active:scale-[0.97]"
            >
              {signedIn ? copy.nav.dashboard : home.hero.cta}
              <ArrowRight className="transition-transform group-hover:translate-x-0.5" size={15} weight="bold" />
            </Link>
            <a href="#product" className="vh-btn-ghost group inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm text-[var(--vh-text)] transition-colors">
              <Play size={13} weight="fill" className="text-[var(--vh-orchid)]" />
              {home.hero.secondary}
            </a>
            <a href="#contact" className="px-2 text-sm text-[var(--vh-soft)] underline-offset-4 transition-colors hover:text-[var(--vh-text)] hover:underline">
              {copy.nav.bookDemo}
            </a>
          </motion.div>
          <motion.p {...enter(0.55)} className="vh-mono mt-8 max-w-[60ch] text-[11px] leading-5 text-[var(--vh-faint)]">
            {home.hero.footnote}
          </motion.p>
        </motion.div>

        <motion.div className="relative" style={reduce ? undefined : { y: panelY, scale: panelScale }}>
          <motion.div
            className="[perspective:1600px]"
            initial={reduce ? false : { opacity: 0, y: 60, rotateX: 18, filter: "blur(10px)" }}
            animate={{ opacity: 1, y: 0, rotateX: 0, filter: "blur(0px)" }}
            transition={{ duration: 1.3, ease: curve.out, delay: 0.25 }}
          >
            <motion.div
              className="relative [transform-style:preserve-3d]"
              style={!wide ? undefined : reduce ? { rotateY: -5, rotateX: 3 } : { rotateY, rotateX }}
            >
              <LiveServicePanel copy={home.panel} ka={locale === "ka"} />
            </motion.div>
          </motion.div>
          {/* Small depth cue in front of the panel. */}
          <motion.div
            aria-hidden="true"
            className="pointer-events-none absolute -right-2 -top-6 hidden lg:block"
            style={reduce ? undefined : { x: frontX, y: frontY }}
          >
            <div className="vh-glass vh-breathe flex items-center gap-2 rounded-full px-3 py-1.5">
              <span className="h-1.5 w-1.5 rounded-full bg-[var(--vh-orchid)]" />
              <span className="vh-mono text-[10px] text-[var(--vh-soft)]">{home.panel.title} · {home.panel.now}</span>
            </div>
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}
