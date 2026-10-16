import { motion, useMotionValue, useReducedMotion, useSpring, useTransform } from "motion/react";
import type { PointerEvent as ReactPointerEvent } from "react";
import { useLocale } from "../../lib/i18n";
import { BrandMark } from "./primitives";

const CHIPS = {
  en: ["Table 4 · seated", "82% of tables seated", "Close day · 2 open", "Nino · 20:30 · 4 guests", "4 staff on duty", "2,868.65 ₾ today"],
  ka: ["მაგიდა 4 · დაკავდა", "მაგიდების 82% დაკავებულია", "დახურვა · 2 ღია", "ნინო · 20:30 · 4 სტუმარი", "4 თანამშრომელი ცვლაში", "დღეს 2,868.65 ₾"],
};

/**
 * Manager page hero: a phone in the middle of a slow orbit of live facts.
 * The ring turns in 3D (chips pass behind the phone), the whole scene leans
 * toward the pointer. The phone screen is a blank slot while the app is reworked.
 */
export function ManagerOrbit() {
  const { locale } = useLocale();
  const chips = CHIPS[locale];
  const reduce = useReducedMotion();
  const px = useMotionValue(0);
  const py = useMotionValue(0);
  const rotateY = useSpring(useTransform(px, [-1, 1], [-14, 14]), { stiffness: 60, damping: 16 });
  const rotateX = useSpring(useTransform(py, [-1, 1], [10, -10]), { stiffness: 60, damping: 16 });

  const move = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.pointerType !== "mouse") return;
    const box = event.currentTarget.getBoundingClientRect();
    px.set(((event.clientX - box.left) / box.width) * 2 - 1);
    py.set(((event.clientY - box.top) / box.height) * 2 - 1);
  };

  return (
    <div
      className="relative mx-auto flex h-[560px] w-full max-w-[900px] items-center justify-center [perspective:1400px] sm:h-[640px]"
      onPointerMove={move}
      onPointerLeave={() => {
        px.set(0);
        py.set(0);
      }}
    >
      <div aria-hidden="true" className="absolute inset-[18%] rounded-full bg-[radial-gradient(closest-side,rgba(154,106,161,0.55),transparent)] blur-3xl" />
      <motion.div className="relative h-full w-full [transform-style:preserve-3d]" style={reduce ? undefined : { rotateX, rotateY }}>
        {/* Orbit ring */}
        <div className="absolute left-1/2 top-1/2 h-0 w-0 [transform-style:preserve-3d] [transform:rotateX(68deg)]">
          <div className={`absolute left-0 top-0 h-0 w-0 [transform-style:preserve-3d] ${reduce ? "" : "vh-orbit"}`}>
            {chips.map((chip, index) => {
              const angle = (index / chips.length) * 360;
              return (
                <div
                  key={chip}
                  className="absolute left-0 top-0 [transform-style:preserve-3d]"
                  style={{ transform: `rotateZ(${angle}deg) translateY(var(--vh-orbit-r)) rotateZ(${-angle}deg)` }}
                >
                  {/* Counter-rotations keep each chip upright and facing the viewer. */}
                  <div className={`${reduce ? "" : "vh-orbit-counter"} [transform-style:preserve-3d]`}>
                    <div className="[transform:rotateX(-68deg)]">
                      <span className="vh-glass vh-mono flex -translate-x-1/2 -translate-y-1/2 items-center gap-2 whitespace-nowrap rounded-full px-3 py-2 text-[11px] text-[var(--vh-text)] sm:text-[12px]">
                        <span className={`h-1.5 w-1.5 rounded-full ${index % 3 === 2 ? "bg-[var(--vh-amber)]" : index % 3 === 1 ? "bg-[var(--vh-sage)]" : "bg-[var(--vh-orchid)]"}`} />
                        {chip}
                      </span>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Phone, standing in the centre of the ring */}
        <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 [transform:translateZ(40px)]">
          <div className="w-[200px] rounded-[38px] border border-white/15 bg-[#0f0e0d] p-[8px] shadow-[0_60px_120px_-30px_rgba(0,0,0,0.95)] sm:w-[230px]">
            <div className="flex aspect-[9/19.5] flex-col gap-2.5 rounded-[30px] bg-[#f4f2ef] p-3.5 pt-9">
              <div className="flex items-center gap-2">
                <BrandMark size={20} />
                <span className="h-2 w-16 rounded-full bg-[#d8d0c9]" />
              </div>
              <div className="rounded-[14px] bg-[#764b7c] p-3">
                <div className="h-2 w-12 rounded-full bg-white/40" />
                <div className="mt-2.5 h-5 w-24 rounded-[6px] bg-white/85" />
              </div>
              <div className="vh-shimmer h-20 rounded-[12px] bg-[linear-gradient(90deg,#e9e5e0_0%,#f6f3ef_40%,#e9e5e0_80%)]" />
              <div className="grid grid-cols-2 gap-2">
                <div className="h-14 rounded-[10px] bg-[#ebe7e2]" />
                <div className="h-14 rounded-[10px] bg-[#e8dcea]" />
              </div>
              <div className="mt-auto h-9 rounded-[14px] bg-white shadow-[0_6px_16px_-8px_rgba(28,26,24,0.3)]" />
            </div>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
