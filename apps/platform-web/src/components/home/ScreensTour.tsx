import { ArrowsSplit, CashRegister, CreditCard, Money, X } from "@phosphor-icons/react";
import { AnimatePresence, motion, useReducedMotion, useScroll, useTransform } from "motion/react";
import { useEffect, useRef, useState } from "react";
import screenCloseDay from "../../assets/screen-manager-closeday.png";
import screenOrder from "../../assets/screen-order-entry.png";
import screenFloor from "../../assets/screen-pos-floor-live.png";
import screenTable from "../../assets/screen-table-payment.png";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy } from "./homeCopy";
import { Rise, SectionOpen, useOnScreen } from "./primitives";

/**
 * One real shift on the real POS. Every frame is a capture of the running
 * Vynic POS (1728×1117 logical, Retina); the only rebuilt piece is the payment
 * dialog, drawn 1:1 from `table_payment_service.dart` and laid over the real
 * table screen exactly where the app shows it.
 *
 * Each step: the screen opens from the point that was just tapped, the camera
 * eases toward what matters, the cursor travels and taps the next control.
 */

type Point = [number, number];
type Step = { src: string; alt: string; focus: Point; zoom: number; tap: Point; overlay?: "payment" };

// Fractions of the screenshot. Taps follow the real flow:
// Table 1 → edit menu → add an item → close table → close the day.
const STEPS: Step[] = [
  { src: screenFloor, alt: "Vynic POS live floor with Table 1 occupied at 404.80 GEL", focus: [0.3, 0.5], zoom: 1.22, tap: [0.262, 0.53] },
  { src: screenTable, alt: "Vynic POS Table 1 check with service fee and 404.80 GEL payable", focus: [0.62, 0.3], zoom: 1.16, tap: [0.902, 0.278] },
  { src: screenOrder, alt: "Vynic POS order editor with Georgian menu categories and GEL prices", focus: [0.3, 0.3], zoom: 1.2, tap: [0.118, 0.117] },
  { src: screenTable, alt: "Vynic POS payment method dialog over the Table 1 check", focus: [0.5, 0.5], zoom: 1.08, tap: [0.385, 0.57], overlay: "payment" },
  { src: screenCloseDay, alt: "Vynic Manager center close-day screen with Z report and open-table warning", focus: [0.55, 0.36], zoom: 1.18, tap: [0.678, 0.418] },
];

const STEP_MS = 7000;
const LOGICAL_WIDTH = 1728;
/** Real app pixels → container-relative units, so the overlay scales 1:1 with the capture. */
const px = (value: number) => `${(value / LOGICAL_WIDTH) * 100}cqw`;

export function ScreensTour() {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale).screens;
  const tour = copy.product.tour;
  const reduce = useReducedMotion();
  const [ref, visible] = useOnScreen<HTMLDivElement>();
  const [active, setActive] = useState(0);
  // The screen being covered stays underneath while the next one opens.
  const [previous, setPrevious] = useState<number | null>(null);
  const [origin, setOrigin] = useState<Point>([0.5, 0.5]);
  const [paused, setPaused] = useState(false);
  const auto = !reduce && visible && !paused;

  const go = (next: number, from?: Point) => {
    if (next === active) return;
    setOrigin(from ?? [0.5, 0.5]);
    setPrevious(active);
    setActive(next);
  };

  useEffect(() => {
    if (!auto) return;
    const timer = window.setTimeout(() => go((active + 1) % STEPS.length, STEPS[active].tap), STEP_MS);
    return () => window.clearTimeout(timer);
  }, [auto, active]);

  // The device frame leans back into place as the section scrolls in.
  const frameRef = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: frameRef, offset: ["start end", "start 30%"] });
  const tilt = useTransform(scrollYProgress, [0, 1], [16, 0]);
  const lift = useTransform(scrollYProgress, [0, 1], [80, 0]);
  const scale = useTransform(scrollYProgress, [0, 1], [0.9, 1]);

  const step = STEPS[active];

  return (
    <section className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        <SectionOpen kicker={home.kicker} title={home.title} body={copy.product.body} />

        <div
          ref={ref}
          className="mt-14 grid grid-cols-[minmax(0,1fr)] gap-6 lg:grid-cols-[300px_minmax(0,1fr)] lg:gap-10"
          onMouseEnter={() => setPaused(true)}
          onMouseLeave={() => setPaused(false)}
        >
          <Rise className="order-2 lg:order-1">
            <div role="tablist" aria-label={copy.product.shiftFlow} className="-mx-4 flex snap-x gap-2 overflow-x-auto px-4 pb-2 lg:mx-0 lg:grid lg:overflow-visible lg:px-0 lg:pb-0">
              {tour.map((item, index) => {
                const on = index === active;
                return (
                  <button
                    key={item.title}
                    type="button"
                    role="tab"
                    aria-selected={on}
                    aria-controls="vh-screen-stage"
                    onClick={() => go(index)}
                    className={`group relative min-w-[220px] snap-start overflow-hidden rounded-[14px] border px-4 py-3.5 text-left transition-colors duration-300 lg:min-w-0 ${
                      on ? "border-[rgba(216,182,222,0.35)] bg-[rgba(118,75,124,0.16)]" : "border-[var(--vh-line)] hover:bg-white/[0.03]"
                    }`}
                  >
                    <span className={`vh-mono block text-[10px] ${on ? "text-[var(--vh-orchid)]" : "text-[var(--vh-faint)]"}`}>
                      {String(index + 1).padStart(2, "0")} · {item.label}
                    </span>
                    <span className={`mt-1 block text-[14px] leading-5 ${on ? "text-[var(--vh-text)]" : "text-[var(--vh-muted)]"}`}>{item.title}</span>
                    <AnimatePresence>
                      {on ? (
                        <motion.span
                          className="block overflow-hidden text-[12px] leading-5 text-[var(--vh-muted)] lg:block"
                          initial={{ height: 0, opacity: 0 }}
                          animate={{ height: "auto", opacity: 1 }}
                          exit={{ height: 0, opacity: 0 }}
                          transition={{ duration: 0.45, ease: curve.out }}
                        >
                          <span className="block pt-2">{item.body}</span>
                        </motion.span>
                      ) : null}
                    </AnimatePresence>
                    <span className="absolute inset-x-0 bottom-0 h-[2px] bg-white/[0.05]">
                      {on ? (
                        <motion.span
                          key={`${active}-${auto}`}
                          className="block h-full origin-left bg-[var(--vh-orchid)]"
                          initial={{ scaleX: 0 }}
                          animate={{ scaleX: auto ? 1 : 0 }}
                          transition={{ duration: auto ? STEP_MS / 1000 : 0, ease: "linear" }}
                        />
                      ) : null}
                    </span>
                  </button>
                );
              })}
            </div>
          </Rise>

          <div ref={frameRef} className="order-1 [perspective:1800px] lg:order-2">
            <motion.div style={reduce ? undefined : { rotateX: tilt, y: lift, scale, transformOrigin: "50% 100%" }} className="relative">
              <div aria-hidden="true" className="absolute -inset-8 -z-10 rounded-[40px] bg-[radial-gradient(ellipse_at_center,rgba(154,106,161,0.3),transparent_70%)] blur-2xl" />
              <div className="rounded-[18px] border border-[var(--vh-line-strong)] bg-[var(--vh-panel)] p-1.5 shadow-[0_60px_120px_-40px_rgba(0,0,0,0.85)] sm:rounded-[22px] sm:p-2.5">
                <div
                  id="vh-screen-stage"
                  role="tabpanel"
                  aria-label={tour[active].title}
                  className="relative aspect-[3456/2234] overflow-hidden rounded-[12px] bg-[#f6f5f2] [container-type:inline-size] sm:rounded-[14px]"
                >
                  {previous !== null ? (
                    <div key={`under-${previous}`} className="absolute inset-0">
                      <div
                        className="absolute inset-0"
                        style={{ transformOrigin: `${STEPS[previous].focus[0] * 100}% ${STEPS[previous].focus[1] * 100}%`, transform: `scale(${reduce ? 1 : STEPS[previous].zoom})` }}
                      >
                        <img src={STEPS[previous].src} alt="" className="h-full w-full object-cover" draggable={false} />
                      </div>
                    </div>
                  ) : null}
                  <motion.div
                    key={`screen-${active}`}
                    className="absolute inset-0"
                    initial={reduce || previous === null ? false : { clipPath: `circle(0% at ${origin[0] * 100}% ${origin[1] * 100}%)` }}
                    animate={{ clipPath: `circle(150% at ${origin[0] * 100}% ${origin[1] * 100}%)` }}
                    transition={{ duration: 1.1, ease: curve.inOut }}
                  >
                    <motion.div
                      className="absolute inset-0"
                      style={{ transformOrigin: `${step.focus[0] * 100}% ${step.focus[1] * 100}%` }}
                      initial={{ scale: 1 }}
                      animate={{ scale: reduce ? 1 : step.zoom }}
                      transition={{ duration: STEP_MS / 1000, ease: [0.33, 0, 0.2, 1] }}
                    >
                      <img src={step.src} alt={step.alt} className="h-full w-full object-cover" draggable={false} />
                      {step.overlay === "payment" ? <PaymentDialog reduce={Boolean(reduce)} /> : null}
                      {!reduce && auto ? <Cursor key={`cursor-${active}`} from={origin} to={step.tap} delay={step.overlay ? 2.6 : 1.6} /> : null}
                    </motion.div>
                  </motion.div>
                  {/* Soft vignette keeps the capture sitting inside the frame. */}
                  <div aria-hidden="true" className="pointer-events-none absolute inset-0 shadow-[inset_0_0_60px_rgba(28,26,24,0.18)]" />
                </div>
              </div>
              <div className="mt-4 flex items-center justify-between gap-4">
                <p className="vh-mono text-[10px] text-[var(--vh-faint)]">Vynic POS · {tour[active].label}</p>
                <p className="vh-mono text-[10px] text-[var(--vh-faint)]">{String(active + 1).padStart(2, "0")} / {String(STEPS.length).padStart(2, "0")}</p>
              </div>
            </motion.div>
          </div>
        </div>
      </div>
    </section>
  );
}

/** A pointer that glides from the last tap to the next control, then taps it. */
function Cursor({ from, to, delay }: { from: Point; to: Point; delay: number }) {
  return (
    <motion.div
      aria-hidden="true"
      className="pointer-events-none absolute z-20"
      initial={{ left: `${from[0] * 100}%`, top: `${from[1] * 100}%`, opacity: 0 }}
      animate={{ left: `${to[0] * 100}%`, top: `${to[1] * 100}%`, opacity: [0, 1, 1, 1] }}
      transition={{ duration: 1.6, ease: curve.inOut, delay }}
    >
      <motion.span
        className="absolute -left-5 -top-5 h-10 w-10 rounded-full border-2 border-[#764b7c] bg-[rgba(118,75,124,0.18)]"
        initial={{ scale: 0, opacity: 0 }}
        animate={{ scale: [0, 1, 1.6], opacity: [0, 1, 0] }}
        transition={{ duration: 0.8, delay: delay + 1.75, ease: "easeOut" }}
      />
      <motion.svg
        width="22"
        height="22"
        viewBox="0 0 24 24"
        className="drop-shadow-[0_4px_8px_rgba(0,0,0,0.35)]"
        animate={{ scale: [1, 1, 0.82, 1] }}
        transition={{ duration: 0.5, delay: delay + 1.6, times: [0, 0.3, 0.6, 1] }}
      >
        <path d="M4 2l15 9.2-6.6 1.4L16 20l-3 1.4-3.6-7.4L4 18.8z" fill="#1c1a18" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
      </motion.svg>
    </motion.div>
  );
}

/**
 * The payment-method dialog, 1:1 with the POS (`TablePaymentService`): white
 * 600-wide panel, teal register icon, amount summary, Cash / Bank POS / Split
 * cards, cancel. Sizes are app pixels mapped to the capture's width.
 */
export function PaymentDialog({ reduce }: { reduce: boolean }) {
  const methods = [
    { label: "ნაღდი ფული", english: "Cash", Icon: Money, color: "#047857" },
    { label: "ბარათით", english: "Bank POS", Icon: CreditCard, color: "#2563EB" },
    { label: "გაყოფილი", english: "Split", Icon: ArrowsSplit, color: "#7C3AED" },
  ];
  return (
    <motion.div
      className="absolute inset-0 z-10 flex items-center justify-center bg-black/55"
      initial={reduce ? false : { opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.3, delay: reduce ? 0 : 1.2 }}
    >
      <motion.div
        className="flex flex-col items-center bg-white text-center"
        style={{
          width: px(600),
          padding: `${px(28)} ${px(28)} ${px(24)}`,
          borderRadius: px(24),
          border: "1px solid #E5E7EB",
          boxShadow: "0 24px 60px rgba(0,0,0,0.28)",
          fontFamily: "'Noto Sans Georgian', 'Geist', sans-serif",
        }}
        initial={reduce ? false : { opacity: 0, scale: 0.92, y: 12 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        transition={{ duration: 0.45, ease: curve.out, delay: reduce ? 0 : 1.25 }}
      >
        <span className="flex items-center justify-center" style={{ padding: px(14), borderRadius: px(16), background: "rgba(15,118,110,0.10)" }}>
          <CashRegister weight="fill" color="#0F766E" style={{ width: px(26), height: px(26) }} />
        </span>
        <p style={{ marginTop: px(16), fontSize: px(20), fontWeight: 800, color: "#111827", letterSpacing: "-0.01em" }}>აირჩიეთ გადახდის მეთოდი</p>
        <p style={{ marginTop: px(4), fontSize: px(13), color: "#6B7280" }}>Select payment method</p>
        <div
          className="flex w-full items-center justify-between"
          style={{ marginTop: px(16), padding: `${px(12)} ${px(16)}`, borderRadius: px(14), background: "#F6F7F9", border: "1px solid #E5E7EB" }}
        >
          <span style={{ fontSize: px(15), fontWeight: 700, color: "#111827" }}>გადასახდელი</span>
          <span style={{ fontSize: px(18), fontWeight: 800, color: "#111827", fontVariantNumeric: "tabular-nums" }}>₾404.80</span>
        </div>
        <div className="flex w-full" style={{ marginTop: px(24), gap: px(14) }}>
          {methods.map(({ label, english, Icon, color }, index) => (
            <motion.div
              key={english}
              className="flex flex-1 flex-col items-center justify-center"
              style={{ height: px(158), padding: px(18), borderRadius: px(18), background: "#F6F7F9", border: "1px solid #E5E7EB" }}
              animate={reduce || index !== 0 ? undefined : { backgroundColor: ["#F6F7F9", "#F6F7F9", "#E3F1EC"] }}
              transition={{ duration: 0.6, delay: 4.15, times: [0, 0.5, 1] }}
            >
              <span style={{ padding: px(14), borderRadius: px(16), background: `${color}1f` }}>
                <Icon weight="fill" color={color} style={{ width: px(28), height: px(28), display: "block" }} />
              </span>
              <span style={{ marginTop: px(14), fontSize: px(16), fontWeight: 700, color: "#111827" }}>{label}</span>
              <span style={{ marginTop: px(2), fontSize: px(12), color: "#6B7280" }}>{english}</span>
            </motion.div>
          ))}
        </div>
        <span className="inline-flex items-center" style={{ marginTop: px(20), gap: px(6), padding: `${px(10)} ${px(18)}`, fontSize: px(14), fontWeight: 600, color: "#6B7280" }}>
          <X style={{ width: px(18), height: px(18) }} />
          გაუქმება
        </span>
      </motion.div>
    </motion.div>
  );
}
