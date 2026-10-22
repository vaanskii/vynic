import { AnimatePresence, motion, useMotionValueEvent, useReducedMotion, useScroll, useSpring, useTransform } from "motion/react";
import { useRef, useState } from "react";
import screenCloseDay from "../../assets/screen-manager-closeday.png";
import screenFloor from "../../assets/screen-pos-floor-live.png";
import screenTable from "../../assets/screen-table-payment.png";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { Tablet } from "./kinetic";
import { Kicker } from "./primitives";
import { PaymentDialog } from "./ScreensTour";
import { getSiteCopy } from "./siteCopy";

const SCREENS = [
  { src: screenFloor, alt: "Vynic POS live floor" },
  { src: screenTable, alt: "Vynic POS Table 1 check" },
  { src: screenTable, alt: "Vynic POS payment method dialog", payment: true },
  { src: screenCloseDay, alt: "Vynic close-day screen" },
];

/**
 * Home's cinematic scene. The section is four screens tall; its stage stays
 * pinned while scrolling turns a real POS tablet through space and swaps one
 * giant word per move: Seat. Order. Pay. Close.
 */
export function ShiftScene() {
  const { locale } = useLocale();
  const copy = getSiteCopy(locale).shift;
  const reduce = useReducedMotion();
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end end"] });
  const progress = useSpring(scrollYProgress, { stiffness: 90, damping: 24, mass: 0.4 });
  const [step, setStep] = useState(0);

  useMotionValueEvent(scrollYProgress, "change", (value) => {
    const next = Math.min(copy.words.length - 1, Math.floor(value * copy.words.length * 0.999));
    if (next !== step) setStep(next);
  });

  // The tablet's flight: in from the right, turning, then square to camera.
  const rotateY = useTransform(progress, [0, 0.35, 0.7, 1], [-38, -14, 12, 0]);
  const rotateX = useTransform(progress, [0, 0.5, 1], [24, 8, 0]);
  const rotateZ = useTransform(progress, [0, 0.5, 1], [-6, 2, 0]);
  const x = useTransform(progress, [0, 0.4, 1], ["18%", "4%", "0%"]);
  const scale = useTransform(progress, [0, 0.85, 1], [0.86, 1, 1.04]);
  const fill = useTransform(scrollYProgress, [0, 1], ["0%", "100%"]);

  if (reduce) {
    return (
      <section ref={ref} className="px-4 py-24 sm:px-6 lg:px-8">
        <div className="mx-auto grid max-w-[1320px] gap-10">
          <Kicker>{copy.kicker}</Kicker>
          {copy.words.map((word, index) => (
            <div key={word} className="grid grid-cols-[minmax(0,1fr)] items-center gap-6 lg:grid-cols-[0.8fr_1.2fr]">
              <div>
                <p className="vh-display text-6xl text-[var(--vh-text)]">{word}</p>
                <p className="mt-3 max-w-sm text-[15px] leading-7 text-[var(--vh-muted)]">{copy.captions[index]}</p>
              </div>
              <img src={SCREENS[index].src} alt={SCREENS[index].alt} className="w-full rounded-[14px]" />
            </div>
          ))}
        </div>
      </section>
    );
  }

  return (
    <section ref={ref} aria-label={copy.words.join(" ")} className="relative h-[420vh]">
      <div className="sticky top-0 flex h-[100dvh] items-center overflow-hidden">
        {/* Giant step number behind everything */}
        <AnimatePresence mode="popLayout">
          <motion.span
            key={step}
            aria-hidden="true"
            className="vh-display pointer-events-none absolute -left-4 bottom-[-6vh] select-none text-[46vh] leading-none text-transparent [-webkit-text-stroke:1px_rgba(216,182,222,0.14)] lg:left-[2vw]"
            initial={{ opacity: 0, y: 80 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -80 }}
            transition={{ duration: 0.8, ease: curve.out }}
          >
            0{step + 1}
          </motion.span>
        </AnimatePresence>

        <div className="relative mx-auto grid w-full max-w-[1320px] grid-cols-[minmax(0,1fr)] items-center gap-8 px-4 sm:px-6 lg:grid-cols-[0.78fr_1.22fr] lg:gap-6 lg:px-8">
          <div className="relative z-10">
            <Kicker>{copy.kicker}</Kicker>
            <div className="relative mt-6 h-[1.1em] text-[4.2rem] sm:text-[7rem] lg:text-[9.5rem]">
              <AnimatePresence mode="popLayout" initial={false}>
                <motion.p
                  key={step}
                  className="vh-display absolute inset-x-0 top-0 whitespace-nowrap text-[var(--vh-text)]"
                  initial={{ opacity: 0, y: "60%", rotateX: -70, filter: "blur(12px)" }}
                  animate={{ opacity: 1, y: "0%", rotateX: 0, filter: "blur(0px)" }}
                  exit={{ opacity: 0, y: "-50%", rotateX: 60, filter: "blur(12px)" }}
                  transition={{ duration: 0.75, ease: curve.out }}
                  style={{ transformPerspective: 900, transformOrigin: "50% 100%" }}
                >
                  {copy.words[step]}
                </motion.p>
              </AnimatePresence>
            </div>
            <div className="relative mt-4 min-h-[56px] max-w-sm">
              <AnimatePresence mode="wait" initial={false}>
                <motion.p
                  key={step}
                  className="text-[15px] leading-7 text-[var(--vh-muted)]"
                  initial={{ opacity: 0, x: -16 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: 16 }}
                  transition={{ duration: 0.45, ease: curve.out }}
                >
                  {copy.captions[step]}
                </motion.p>
              </AnimatePresence>
            </div>
            {/* Progress: four ticks that fill with scroll */}
            <div className="mt-8 flex max-w-sm items-center gap-3">
              {copy.words.map((word, index) => (
                <span key={word} className={`vh-mono text-[10px] transition-colors duration-500 ${index === step ? "text-[var(--vh-orchid)]" : "text-[var(--vh-faint)]"}`}>
                  0{index + 1}
                </span>
              ))}
              <span className="relative h-px flex-1 bg-white/10">
                <motion.span className="absolute inset-y-0 left-0 bg-[var(--vh-orchid)] shadow-[0_0_10px_rgba(216,182,222,0.8)]" style={{ width: fill }} />
              </span>
            </div>
          </div>

          <div className="relative [perspective:1800px]">
            <div aria-hidden="true" className="absolute inset-[8%] -z-10 rounded-full bg-[radial-gradient(closest-side,rgba(154,106,161,0.5),transparent)] blur-3xl" />
            <motion.div style={{ x, scale }} className="[transform-style:preserve-3d]">
              <Tablet rotateX={rotateX} rotateY={rotateY} rotateZ={rotateZ}>
                <div className="relative aspect-[3456/2234] [container-type:inline-size]">
                  <AnimatePresence initial={false}>
                    <motion.div
                      key={step}
                      className="absolute inset-0"
                      initial={{ clipPath: "inset(0% 0% 100% 0%)" }}
                      animate={{ clipPath: "inset(0% 0% 0% 0%)" }}
                      exit={{ opacity: 1 }}
                      transition={{ duration: 0.8, ease: curve.inOut }}
                    >
                      <img src={SCREENS[step].src} alt={SCREENS[step].alt} className="h-full w-full object-cover" draggable={false} />
                      {SCREENS[step].payment ? <PaymentDialog reduce={false} /> : null}
                    </motion.div>
                  </AnimatePresence>
                  {/* A light sweep across the glass on every change */}
                  <motion.span
                    key={`sweep-${step}`}
                    aria-hidden="true"
                    className="pointer-events-none absolute inset-y-0 w-1/3 bg-[linear-gradient(100deg,transparent,rgba(255,255,255,0.45),transparent)]"
                    initial={{ left: "-40%" }}
                    animate={{ left: "120%" }}
                    transition={{ duration: 1.1, ease: curve.inOut }}
                  />
                </div>
              </Tablet>
            </motion.div>
          </div>
        </div>
      </div>
    </section>
  );
}
