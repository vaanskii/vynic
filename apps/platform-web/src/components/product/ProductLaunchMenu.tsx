import { useEffect, useState } from "react";
import { useReducedMotion } from "motion/react";
import vynicLogo from "../../assets/vynic-logo.png";
import { useLocale } from "../../lib/i18n";

export function ProductLaunchMenu({ className = "" }: { className?: string }) {
  const reduceMotion = useReducedMotion();
  const { copy, locale } = useLocale();
  const launchChecks = locale === "ka" ? ["სართულის გეგმა", "რეზერვაციები", "ოფლაინ სერვისი"] : ["FLOOR PLAN", "RESERVATIONS", "OFFLINE SERVICE"];
  const [activeCheck, setActiveCheck] = useState(2);

  useEffect(() => {
    if (reduceMotion) return;

    const interval = window.setInterval(() => {
      setActiveCheck((current) => (current + 1) % launchChecks.length);
    }, 1500);

    return () => window.clearInterval(interval);
  }, [reduceMotion]);

  return (
    <figure
      className={`vynic-neu-surface vynic-image-frame group relative w-full overflow-hidden rounded-[8px] border border-vynic-border bg-vynic-surface shadow-[0_22px_70px_color-mix(in_srgb,var(--vynic-charcoal)_10%,transparent)] motion-safe:transition-transform motion-safe:duration-500 motion-safe:ease-[cubic-bezier(0.16,1,0.3,1)] motion-safe:hover:-translate-y-1 ${className}`}
    >
      <div className="aspect-[5/3] w-full">
        <div className="relative h-full w-full rounded-[14px] border border-[#a9a49e] bg-[#d7d3ce] px-[9px] pb-[33px] pt-[9px] shadow-[0_24px_48px_rgba(0,0,0,0.26)]">
          <div
            className="relative h-full w-full overflow-hidden rounded-[7px] border-[5px] border-[#302e2b] bg-[#22201e] shadow-[inset_0_0_0_1px_#5b5752]"
            role="img"
            aria-label="Vynic POS branded loading menu"
          >
            <span className="vynic-launch-boot-line pointer-events-none absolute inset-y-0 left-0 z-10 w-[24%]" />
            <div className="vynic-launch-splash relative z-20 flex h-full flex-col items-center justify-center overflow-hidden text-[#f7f6f4]">
              <div className="vynic-launch-mark flex h-9 w-9 items-center justify-center rounded-[9px] bg-[#f2edf7] p-1.5 sm:h-14 sm:w-14 sm:rounded-[12px] sm:p-2">
                <img className="h-full w-full object-contain" src={vynicLogo} alt="" />
              </div>
              <p className="mt-2 hidden font-vynic-mono text-[8px] font-semibold tracking-[0.18em] text-[#f7f6f4] sm:mt-4 sm:block sm:text-[10px]">
                VYNIC POS
              </p>
              <p className="vynic-launch-message mt-2 max-w-[14ch] text-center text-[15px] font-semibold leading-[1.05] text-[#f7f6f4] sm:mt-5 sm:max-w-[16ch] sm:text-2xl">
                {locale === "ka" ? "შექმნილია დატვირთული სერვისისთვის." : "Built for the rush."}
              </p>
              <p className="mt-2 font-vynic-mono text-[6px] tracking-[0.14em] text-[#b9a8c4] sm:mt-4 sm:text-[8px]">
                {locale === "ka" ? "სერვისი მზადდება" : "PREPARING SERVICE"}
              </p>
              <div className="mt-3 flex gap-1 sm:mt-5" aria-hidden="true">
                <span className="vynic-launch-loader h-1 w-5 rounded-full bg-[#b9a8c4] sm:w-7" />
                <span className="vynic-launch-loader h-1 w-5 rounded-full bg-[#b9a8c4] sm:w-7 [animation-delay:120ms]" />
                <span className="vynic-launch-loader h-1 w-5 rounded-full bg-[#b9a8c4] sm:w-7 [animation-delay:240ms]" />
              </div>
              <div className="mt-4 grid w-[78%] max-w-[300px] gap-1 border-y border-white/10 py-2 font-vynic-mono text-[6px] tracking-[0.1em] text-[#d8d0c9] sm:mt-7 sm:w-[68%] sm:gap-2 sm:py-3 sm:text-[8px]">
                {launchChecks.map((item, index) => {
                  const loading = !reduceMotion && index === activeCheck;

                  return (
                    <div key={item} className="flex items-center justify-between gap-2 sm:gap-4">
                      <span className="flex items-center gap-1 sm:gap-2">
                        <span className={`h-1.5 w-1.5 rounded-full ${loading ? "vynic-launch-dot bg-[#b9a8c4]" : "bg-[#586d57]"}`} />
                        {item}
                      </span>
                      <span className={loading ? "text-[#b9a8c4]" : "text-[#8f8296]"}>
                        {loading ? (locale === "ka" ? "იტვირთება" : "LOADING") : (locale === "ka" ? "მზადაა" : "READY")}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
          <span className="absolute bottom-[11px] left-1/2 -translate-x-1/2 font-vynic-mono text-[8px] font-bold tracking-[0.18em] text-[#6f6a64]">
            VYNIC POS
          </span>
          <span className="absolute bottom-[4px] left-1/2 h-[6px] w-[18%] -translate-x-1/2 rounded-full bg-[#9b958e] shadow-[0_2px_2px_rgba(0,0,0,0.18)]" />
        </div>
      </div>
      <div className="vynic-frame-shine pointer-events-none absolute inset-0" />
    </figure>
  );
}
