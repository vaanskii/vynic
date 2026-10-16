import { CalendarCheck, ChartLineUp, LockKey, SquaresFour, UsersThree } from "@phosphor-icons/react";
import type { Icon } from "@phosphor-icons/react";
import { AnimatePresence, motion, useMotionValue, useReducedMotion, useScroll, useSpring, useTransform, type PanInfo } from "motion/react";
import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent as ReactPointerEvent } from "react";
import { useLocale } from "../../lib/i18n";
import { curve } from "../../lib/motion";
import { getHomeCopy } from "./homeCopy";
import { BrandMark, Rise, SectionOpen, useOnScreen } from "./primitives";

/**
 * Manager app slots. The app is being reworked, so every tab is a blank,
 * skeleton screen for now; drop a capture into `src` (9:19.5 portrait) and
 * the phone shows it instead — interaction and layout stay as they are.
 */
const SCREENS: Array<{ icon: Icon; layout: "today" | "tables" | "list" | "people" | "close"; src?: string }> = [
  { icon: ChartLineUp, layout: "today" },
  { icon: SquaresFour, layout: "tables" },
  { icon: CalendarCheck, layout: "list" },
  { icon: UsersThree, layout: "people" },
  { icon: LockKey, layout: "close" },
];

export function ManagerApp({ bare = false }: { bare?: boolean }) {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale).manager;
  const reduce = useReducedMotion();
  const [active, setActive] = useState(0);
  const [direction, setDirection] = useState(1);
  const [ref, visible] = useOnScreen<HTMLDivElement>();
  const [touched, setTouched] = useState(false);

  // What each tab is for, from the shared manager copy.
  const details = [
    { title: copy.manager.practicalTitle, body: copy.manager.body },
    { title: copy.manager.points[3], body: copy.capabilities[2]?.body ?? "" },
    { title: copy.manager.points[2], body: copy.capabilities[3]?.body ?? "" },
    { title: copy.manager.roleTitle, body: copy.manager.roleBody },
    { title: copy.manager.closeTitle, body: copy.manager.closeBody },
  ];

  const go = (next: number) => {
    const wrapped = (next + SCREENS.length) % SCREENS.length;
    setDirection(wrapped > active || (active === SCREENS.length - 1 && wrapped === 0) ? 1 : -1);
    setActive(wrapped);
  };

  // Gentle auto-play until the visitor takes over.
  useEffect(() => {
    if (reduce || !visible || touched) return;
    const timer = window.setTimeout(() => go(active + 1), 4200);
    return () => window.clearTimeout(timer);
  });

  const take = (next: number) => {
    setTouched(true);
    go(next);
  };

  const onKey = (event: KeyboardEvent) => {
    if (event.key === "ArrowRight" || event.key === "ArrowDown") {
      event.preventDefault();
      take(active + 1);
    } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
      event.preventDefault();
      take(active - 1);
    }
  };

  const onDragEnd = (_: unknown, info: PanInfo) => {
    if (info.offset.x < -50 || info.velocity.x < -400) take(active + 1);
    else if (info.offset.x > 50 || info.velocity.x > 400) take(active - 1);
  };

  // Scroll: the phone rises and straightens; the ghost phone drifts slower.
  const stageRef = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({ target: stageRef, offset: ["start end", "end start"] });
  const phoneY = useTransform(scrollYProgress, [0, 1], [90, -90]);
  const ghostY = useTransform(scrollYProgress, [0, 1], [30, -30]);
  const phoneRotate = useTransform(scrollYProgress, [0, 0.5, 1], [-8, 0, 6]);

  // Pointer tilt on fine pointers.
  const px = useMotionValue(0);
  const py = useMotionValue(0);
  const tiltY = useSpring(useTransform(px, [-1, 1], [-10, 10]), { stiffness: 80, damping: 16 });
  const tiltX = useSpring(useTransform(py, [-1, 1], [8, -8]), { stiffness: 80, damping: 16 });
  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.pointerType !== "mouse") return;
    const box = event.currentTarget.getBoundingClientRect();
    px.set(((event.clientX - box.left) / box.width) * 2 - 1);
    py.set(((event.clientY - box.top) / box.height) * 2 - 1);
  };

  const screen = SCREENS[active];

  return (
    <section className={`relative px-4 sm:px-6 lg:px-8 ${bare ? "pb-24 pt-2 lg:pb-32" : "py-24 lg:py-32"}`}>
      <div ref={ref} className="mx-auto max-w-[1320px]">
        {bare ? null : <SectionOpen kicker={home.kicker} title={home.title} body={copy.manager.body} />}

        <div className={`${bare ? "" : "mt-14 "}grid grid-cols-[minmax(0,1fr)] items-center gap-12 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)] lg:gap-20`}>
          {/* Phone */}
          <div
            ref={stageRef}
            className="relative mx-auto flex w-full max-w-[420px] justify-center py-6 [perspective:1400px]"
            onPointerMove={onPointerMove}
            onPointerLeave={() => {
              px.set(0);
              py.set(0);
            }}
          >
            <div aria-hidden="true" className="absolute inset-x-0 top-1/2 -z-10 h-[70%] -translate-y-1/2 rounded-full bg-[radial-gradient(closest-side,rgba(154,106,161,0.45),transparent)] blur-2xl" />
            {/* Ghost phone behind, for depth */}
            <motion.div
              aria-hidden="true"
              className="absolute right-[2%] top-[12%] hidden h-[78%] w-[46%] rounded-[34px] border border-[var(--vh-line)] bg-[var(--vh-panel)]/70 sm:block"
              style={reduce ? { rotate: 8 } : { y: ghostY, rotate: 8 }}
            />
            <motion.div style={reduce ? undefined : { y: phoneY, rotateZ: phoneRotate }}>
              <motion.div
                className="relative w-[260px] rounded-[44px] border border-[var(--vh-line-strong)] bg-[#0f0e0d] p-[10px] shadow-[0_60px_120px_-30px_rgba(0,0,0,0.9),0_0_0_1px_rgba(247,246,244,0.04)_inset] sm:w-[290px]"
                style={reduce ? undefined : { rotateY: tiltY, rotateX: tiltX }}
              >
                <div className="relative aspect-[9/19.5] overflow-hidden rounded-[34px] bg-[#f4f2ef]">
                  {/* Status bar + island */}
                  <div className="absolute inset-x-0 top-0 z-20 flex items-center justify-between px-6 pt-3 text-[10px] font-semibold text-[#1c1a18]">
                    <span>21:00</span>
                    <span className="h-[22px] w-[84px] rounded-full bg-[#0f0e0d]" />
                    <span className="flex gap-1">
                      <span className="h-2 w-3 rounded-[2px] bg-[#1c1a18]" />
                      <span className="h-2 w-4 rounded-[2px] border border-[#1c1a18]" />
                    </span>
                  </div>
                  <motion.div
                    className="absolute inset-0 cursor-grab touch-pan-y active:cursor-grabbing"
                    drag={reduce ? false : "x"}
                    dragConstraints={{ left: 0, right: 0 }}
                    dragElastic={0.18}
                    onDragEnd={onDragEnd}
                  >
                    <AnimatePresence initial={false} custom={direction} mode="popLayout">
                      <motion.div
                        key={active}
                        custom={direction}
                        className="absolute inset-0 px-4 pb-20 pt-12"
                        variants={{
                          enter: (dir: number) => ({ x: `${dir * 100}%`, opacity: 0.4 }),
                          center: { x: "0%", opacity: 1 },
                          exit: (dir: number) => ({ x: `${dir * -40}%`, opacity: 0, scale: 0.94 }),
                        }}
                        initial={reduce ? false : "enter"}
                        animate="center"
                        exit="exit"
                        transition={{ duration: 0.55, ease: curve.out }}
                      >
                        {screen.src ? (
                          <img src={screen.src} alt={home.tabs[active]} className="absolute inset-0 h-full w-full object-cover" draggable={false} />
                        ) : (
                          <BlankScreen layout={screen.layout} title={home.tabs[active]} />
                        )}
                      </motion.div>
                    </AnimatePresence>
                  </motion.div>
                  {/* Bottom navigation (part of the phone UI) */}
                  <div className="absolute inset-x-3 bottom-3 z-20 flex items-center justify-between rounded-[22px] bg-white/90 px-2 py-2 shadow-[0_10px_30px_-10px_rgba(28,26,24,0.35)]">
                    {SCREENS.map(({ icon: TabIcon }, index) => (
                      <button
                        key={home.tabs[index]}
                        type="button"
                        tabIndex={-1}
                        aria-hidden="true"
                        onClick={() => take(index)}
                        className={`relative flex h-9 w-9 items-center justify-center rounded-[12px] transition-colors ${index === active ? "text-white" : "text-[#8a827b]"}`}
                      >
                        {index === active ? (
                          <motion.span layoutId="vh-manager-pill" className="absolute inset-0 rounded-[12px] bg-[#764b7c]" transition={{ duration: 0.45, ease: curve.out }} />
                        ) : null}
                        <TabIcon className="relative" size={17} weight={index === active ? "fill" : "regular"} />
                      </button>
                    ))}
                  </div>
                </div>
              </motion.div>
            </motion.div>
          </div>

          {/* Tabs + detail */}
          <div>
            <Rise>
              <div role="tablist" aria-label={home.kicker} onKeyDown={onKey} className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-2 lg:mx-0 lg:grid lg:overflow-visible lg:px-0">
                {home.tabs.map((tab, index) => {
                  const on = index === active;
                  const TabIcon = SCREENS[index].icon;
                  return (
                    <button
                      key={tab}
                      type="button"
                      role="tab"
                      aria-selected={on}
                      tabIndex={on ? 0 : -1}
                      onClick={() => take(index)}
                      className={`group flex min-w-max items-center gap-3 rounded-[14px] border px-4 py-3 text-left transition-colors duration-300 lg:min-w-0 ${
                        on ? "border-[rgba(216,182,222,0.35)] bg-[rgba(118,75,124,0.16)]" : "border-[var(--vh-line)] hover:bg-white/[0.03]"
                      }`}
                    >
                      <TabIcon size={18} weight={on ? "fill" : "regular"} className={on ? "text-[var(--vh-orchid)]" : "text-[var(--vh-faint)]"} />
                      <span className={`text-[14px] ${on ? "text-[var(--vh-text)]" : "text-[var(--vh-muted)]"}`}>{tab}</span>
                      <span className="vh-mono ml-auto hidden text-[10px] text-[var(--vh-faint)] lg:inline">{String(index + 1).padStart(2, "0")}</span>
                    </button>
                  );
                })}
              </div>
            </Rise>
            <div className="relative mt-6 min-h-[150px]">
              <AnimatePresence mode="wait" initial={false}>
                <motion.div
                  key={active}
                  initial={reduce ? false : { opacity: 0, y: 14 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  transition={{ duration: 0.4, ease: curve.out }}
                >
                  <h3 className="vh-sub text-[1.75rem] text-[var(--vh-text)]">{details[active].title}</h3>
                  <p className="mt-3 max-w-md text-[15px] leading-7 text-[var(--vh-muted)]">{details[active].body}</p>
                </motion.div>
              </AnimatePresence>
            </div>
            <p className="vh-mono mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-[10px] text-[var(--vh-faint)]">
              <span>← → {home.hint}</span>
              <span className="inline-flex items-center gap-1.5">
                <span className="vh-blink h-1.5 w-1.5 rounded-full bg-[var(--vh-amber)]" />
                {home.soon}
              </span>
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}

/** A quiet skeleton of each manager screen — a blank waiting for the real capture. */
function BlankScreen({ layout, title }: { layout: (typeof SCREENS)[number]["layout"]; title: string }) {
  const bar = "vh-shimmer rounded-[8px] bg-[linear-gradient(90deg,#e9e5e0_0%,#f6f3ef_40%,#e9e5e0_80%)]";
  return (
    <div className="flex h-full flex-col gap-3" aria-label={title}>
      <div className="flex items-center gap-2">
        <BrandMark size={22} />
        <span className="text-[13px] font-semibold text-[#1c1a18]">{title}</span>
      </div>
      {layout === "today" ? (
        <>
          <div className="rounded-[16px] bg-[#764b7c] p-3">
            <div className="h-2 w-16 rounded-full bg-white/40" />
            <div className="mt-3 h-6 w-28 rounded-[6px] bg-white/80" />
            <div className="mt-3 flex gap-2">
              <div className="h-8 flex-1 rounded-[8px] bg-white/20" />
              <div className="h-8 flex-1 rounded-[8px] bg-white/20" />
            </div>
          </div>
          <div className={`${bar} h-24`} />
          <div className="grid grid-cols-2 gap-2">
            <div className={`${bar} h-16`} />
            <div className={`${bar} h-16`} />
          </div>
        </>
      ) : layout === "tables" ? (
        <div className="grid grid-cols-3 gap-2">
          {Array.from({ length: 12 }, (_, index) => (
            <div key={index} className={`aspect-square rounded-[10px] ${[1, 4, 6, 9].includes(index) ? "bg-[#e8dcea]" : index === 7 ? "bg-[#f1e6d6]" : "bg-[#ebe7e2]"}`} />
          ))}
        </div>
      ) : layout === "list" ? (
        Array.from({ length: 5 }, (_, index) => (
          <div key={index} className="flex items-center gap-3 rounded-[12px] bg-white p-2.5">
            <div className="h-8 w-8 rounded-full bg-[#e8dcea]" />
            <div className="flex-1">
              <div className={`${bar} h-2.5 w-3/4`} />
              <div className={`${bar} mt-1.5 h-2 w-1/2`} />
            </div>
          </div>
        ))
      ) : layout === "people" ? (
        <>
          <div className="flex -space-x-2">
            {Array.from({ length: 4 }, (_, index) => (
              <div key={index} className="h-9 w-9 rounded-full border-2 border-[#f4f2ef] bg-[#d8c4dc]" />
            ))}
          </div>
          {Array.from({ length: 4 }, (_, index) => (
            <div key={index} className="flex items-center justify-between rounded-[12px] bg-white p-3">
              <div className={`${bar} h-2.5 w-24`} />
              <div className="h-5 w-12 rounded-full bg-[#efe7f1]" />
            </div>
          ))}
        </>
      ) : (
        <>
          <div className={`${bar} h-20`} />
          <div className="rounded-[12px] border border-[#ecdcc0] bg-[#fbf4e8] p-3">
            <div className="h-2.5 w-24 rounded-full bg-[#ead7b4]" />
            <div className="mt-2 h-2 w-36 rounded-full bg-[#f1e4cc]" />
          </div>
          <div className="mt-auto h-10 rounded-[12px] bg-[#764b7c]" />
        </>
      )}
    </div>
  );
}
