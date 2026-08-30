import { useEffect, useRef } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useReducedMotion } from "motion/react";
import { ScreenshotSpec } from "../../data/siteContent";
import { PosScreenReplica } from "./PosScreenReplica";
import { useLocale } from "../../lib/i18n";

gsap.registerPlugin(ScrollTrigger);

type ProductScreenshotProps = {
  spec: ScreenshotSpec;
  imageSrc?: string;
  className?: string;
  compact?: boolean;
  mobile?: boolean;
  fill?: boolean;
  live?: boolean;
  onLiveStageChange?: (stage: number) => void;
};

export function ProductScreenshot({
  spec,
  imageSrc,
  className = "",
  compact = false,
  mobile = false,
  fill = false,
  live = false,
  onLiveStageChange,
}: ProductScreenshotProps) {
  const source = imageSrc ?? spec.src;
  const hasVisual = Boolean(source || spec.replica);
  const isReplica = Boolean(spec.replica);
  const figureRef = useRef<HTMLElement>(null);
  const reduceMotion = useReducedMotion();
  const figureClass = fill ? "h-full w-full" : mobile ? "mx-auto max-w-[300px]" : "w-full";
  const frameClass = fill ? "h-full w-full" : mobile ? "aspect-[9/14] w-full" : spec.replica === "floor" ? "aspect-[5/3] w-full" : "aspect-[16/10] w-full";

  useEffect(() => {
    if (reduceMotion || !figureRef.current) return;
    const figure = figureRef.current;

    const ctx = gsap.context(() => {
      const timeline = gsap.timeline({
        scrollTrigger: {
          trigger: figure,
          start: "top 86%",
          once: true,
        },
      });

      timeline.fromTo(
        figure,
        { autoAlpha: 0, y: 30, scale: 0.985, rotateX: 2 },
        {
          autoAlpha: 1,
          y: 0,
          scale: 1,
          rotateX: 0,
          duration: 0.95,
          ease: "power3.out",
        },
      );

    }, figureRef.current);

    return () => ctx.revert();
  }, [reduceMotion, source]);

  return (
    <figure
      ref={figureRef}
      className={`vynic-neu-surface vynic-image-frame group relative overflow-hidden rounded-[8px] border border-vynic-border bg-vynic-surface shadow-[0_22px_70px_color-mix(in_srgb,var(--vynic-charcoal)_10%,transparent)] motion-safe:transition-transform motion-safe:duration-500 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)] motion-safe:hover:-translate-y-1 ${figureClass} ${className}`}
    >
      <div
        className={frameClass}
        style={mobile || isReplica ? undefined : { aspectRatio: spec.aspect }}
      >
        {spec.replica ? (
          <div className="relative h-full w-full rounded-[14px] border border-[#a9a49e] bg-[#d7d3ce] px-[9px] pt-[9px] pb-[33px] shadow-[0_24px_48px_rgba(0,0,0,0.26)]">
            <div className="h-full w-full overflow-hidden rounded-[7px] border-[5px] border-[#302e2b] bg-[#302e2b] shadow-[inset_0_0_0_1px_#5b5752]">
              <PosScreenReplica kind={spec.replica} live={live} onLiveStageChange={onLiveStageChange} />
            </div>
            <span className="absolute bottom-[11px] left-1/2 -translate-x-1/2 font-vynic-mono text-[8px] font-bold tracking-[0.18em] text-[#6f6a64]">VYNIC POS</span>
            <span className="absolute bottom-[4px] left-1/2 h-[6px] w-[18%] -translate-x-1/2 rounded-full bg-[#9b958e] shadow-[0_2px_2px_rgba(0,0,0,0.18)]" />
          </div>
        ) : source ? (
          <img
            className="h-full w-full bg-vynic-background object-contain"
            src={source}
            alt={spec.alt}
            loading={spec.priority ? "eager" : "lazy"}
            fetchPriority={spec.priority ? "high" : "auto"}
            style={{ objectPosition: spec.objectPosition ?? "top center" }}
          />
        ) : (
          <MockScreen spec={spec} compact={compact} mobile={mobile} />
        )}
      </div>
      {hasVisual ? <div className="vynic-frame-shine pointer-events-none absolute inset-0" /> : null}
      {hasVisual && spec.facts?.length ? (
        <figcaption className="flex flex-wrap gap-2 border-t border-vynic-border bg-vynic-background p-3">
          {spec.facts.map((fact) => (
            <span
              key={fact}
              className="rounded-[8px] border border-vynic-border bg-vynic-surface px-3 py-1.5 font-vynic-mono text-[10px] font-semibold text-vynic-charcoal"
            >
              {fact}
            </span>
          ))}
        </figcaption>
      ) : null}
    </figure>
  );
}

function MockScreen({ spec, compact, mobile }: { spec: ScreenshotSpec; compact: boolean; mobile: boolean }) {
  const { copy, locale } = useLocale();
  const s = copy.screen;
  const filename = spec.filename.toLowerCase();
  const kind = filename.includes("manager-mobile")
    ? "mobile"
    : filename.includes("website-reservation")
      ? "reservation"
      : filename.includes("website-preorder")
        ? "preorder"
        : "staff";

  if (kind === "mobile") {
    return (
      <div className="flex h-full items-center justify-center bg-[#ebe7e2] p-4 sm:p-8">
        <div className="h-[94%] w-full max-w-[230px] overflow-hidden rounded-[26px] border-[5px] border-[#2b2927] bg-[#f7f6f4] shadow-[0_18px_30px_rgba(34,32,30,0.2)]">
          <div className="flex items-center justify-between px-4 py-3 text-[9px] font-semibold text-[#6f6a64]">
            <span>09:42</span>
            <span className="rounded-full bg-[#dfe8dc] px-2 py-1 text-[#586d57]">LIVE</span>
          </div>
          <div className="border-t border-[#ded8d1] px-4 py-4">
            <p className="font-vynic-mono text-[9px] font-semibold uppercase tracking-[0.12em] text-[#764b7c]">
            {s.managerView}
            </p>
            <h3 className="mt-2 text-lg font-semibold text-[#22201e]">{s.tonight}</h3>
            <div className="mt-4 grid grid-cols-2 gap-2">
              {[
                ["12", s.tables],
                ["08", s.bookings],
                ["4,280", s.gelToday],
                ["03", s.openChecks],
              ].map(([value, label]) => (
                <div key={label} className="rounded-[8px] border border-[#ded8d1] bg-white p-3">
                  <p className="text-base font-semibold text-[#22201e]">{value}</p>
                  <p className="mt-1 text-[9px] text-[#6f6a64]">{label}</p>
                </div>
              ))}
            </div>
            <div className="mt-4 rounded-[8px] bg-[#22201e] p-3 text-[#f7f6f4]">
              <p className="text-[9px] text-[#d8d0c9]">{s.nextReservation}</p>
              <p className="mt-1 text-sm font-semibold">Table 8 · 20:30</p>
              <div className="mt-3 h-1 rounded-full bg-[#4a4541]"><div className="h-full w-2/3 rounded-full bg-[#b9a8c4]" /></div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  const isStaff = kind === "staff";
  const title = isStaff ? s.managerCenter : kind === "reservation" ? s.reserveTable : s.addToBooking;

  return (
    <div className="h-full overflow-hidden bg-[#f0ede9] p-4 sm:p-7">
      <div className="h-full overflow-hidden rounded-[8px] border border-[#ded8d1] bg-[#fffdfa] shadow-[0_12px_24px_rgba(34,32,30,0.08)]">
        <div className="flex items-center justify-between border-b border-[#ded8d1] px-4 py-3 sm:px-5">
          <div className="flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-[#764b7c]" />
            <span className="font-vynic-mono text-[9px] font-semibold uppercase tracking-[0.12em] text-[#6f6a64]">Vynic workspace</span>
          </div>
          <span className="font-vynic-mono text-[9px] text-[#6f6a64]">{isStaff ? "ADMIN" : "GUEST FLOW"}</span>
        </div>
        <div className="p-4 sm:p-6">
          <div className="flex items-end justify-between gap-4">
            <div>
              <p className="font-vynic-mono text-[9px] font-semibold uppercase tracking-[0.12em] text-[#764b7c]">{isStaff ? s.control : s.reservation}</p>
              <h3 className="mt-2 text-xl font-semibold text-[#22201e] sm:text-2xl">{title}</h3>
            </div>
            <span className="rounded-full bg-[#dfe8dc] px-3 py-1.5 text-[9px] font-semibold text-[#586d57]">{isStaff ? (locale === "ka" ? "დღეს" : "Today") : s.step}</span>
          </div>

          {isStaff ? <StaffMock /> : kind === "reservation" ? <ReservationMock /> : <PreorderMock />}
        </div>
      </div>
      {compact ? null : <div className="pointer-events-none absolute inset-0" />}
    </div>
  );
}

function ReservationMock() {
  return (
    <div className="mt-5 grid gap-3">
      <div className="grid grid-cols-3 gap-2">
        {["MON 22", "TUE 23", "WED 24"].map((date, index) => <div key={date} className={`rounded-[8px] border p-3 text-center text-[10px] font-semibold ${index === 1 ? "border-[#764b7c] bg-[#f1eaf2] text-[#764b7c]" : "border-[#ded8d1] text-[#6f6a64]"}`}>{date}</div>)}
      </div>
      <div className="grid gap-2 sm:grid-cols-2">
        {[["20:00", "Table 4", "6 guests"], ["20:30", "Table 8", "4 guests"], ["21:00", "Table 2", "2 guests"], ["21:30", "Table 6", "8 guests"]].map(([time, table, guests], index) => <div key={time} className={`flex items-center justify-between rounded-[8px] border p-3 ${index === 1 ? "border-[#764b7c] bg-[#f1eaf2]" : "border-[#ded8d1]"}`}><div><p className="text-xs font-semibold text-[#22201e]">{time}</p><p className="mt-1 text-[10px] text-[#6f6a64]">{table} · {guests}</p></div><span className="text-[10px] font-semibold text-[#764b7c]">Select</span></div>)}
      </div>
    </div>
  );
}

function PreorderMock() {
  return (
    <div className="mt-5 grid gap-3 sm:grid-cols-[1fr_0.6fr]">
      <div className="grid gap-2">
        {[['Khachapuri', '25.00 GEL'], ['Seasonal salad', '18.00 GEL'], ['Lemonade', '7.50 GEL']].map(([name, price]) => <div key={name} className="flex items-center justify-between rounded-[8px] border border-[#ded8d1] p-3"><div><p className="text-xs font-semibold text-[#22201e]">{name}</p><p className="mt-1 text-[10px] text-[#6f6a64]">Available for preorder</p></div><span className="text-xs font-semibold text-[#764b7c]">{price}</span></div>)}
      </div>
      <div className="rounded-[8px] bg-[#22201e] p-4 text-[#f7f6f4]"><p className="text-[10px] text-[#d8d0c9]">Attached to</p><p className="mt-1 text-sm font-semibold">Table 8</p><div className="mt-6 flex items-end justify-between border-t border-white/15 pt-3"><span className="text-[10px] text-[#d8d0c9]">Preorder total</span><span className="text-lg font-semibold">50.50 GEL</span></div></div>
    </div>
  );
}

function StaffMock() {
  return (
    <div className="mt-5 grid gap-3 sm:grid-cols-[0.72fr_1fr]">
      <div className="grid grid-cols-2 gap-2">
        {[['04', 'Team'], ['03', 'Roles'], ['12', 'Open checks'], ['01', 'Alert']].map(([value, label]) => <div key={label} className="rounded-[8px] border border-[#ded8d1] p-3"><p className="text-lg font-semibold text-[#22201e]">{value}</p><p className="mt-1 text-[10px] text-[#6f6a64]">{label}</p></div>)}
      </div>
      <div className="grid gap-2">
        {[['Mariam', 'Manager', 'Full access'], ['Giorgi', 'Supervisor', 'Floor + close'], ['Tako', 'Waiter', 'POS floor']].map(([name, role, access]) => <div key={name} className="flex items-center justify-between rounded-[8px] border border-[#ded8d1] px-4 py-3"><div><p className="text-xs font-semibold text-[#22201e]">{name}</p><p className="mt-1 text-[10px] text-[#6f6a64]">{role}</p></div><span className="text-[10px] text-[#6f6a64]">{access}</span></div>)}
      </div>
    </div>
  );
}
