import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { Fragment, useLayoutEffect, useRef } from "react";
import { useLocale } from "../../lib/i18n";
import { motionQuery } from "../../lib/motion";
import { BrandMark } from "./primitives";
import { getHomeCopy } from "./homeCopy";

gsap.registerPlugin(ScrollTrigger);

/**
 * The page's turn: a plum tile the size of the Vynic mark opens to fill the
 * screen, the statement rises inside it, then the tile closes into a soft
 * lozenge and lets the page continue. Scrubbed by native scroll on capable
 * screens; otherwise a static plum band with the statement.
 */
export function PortalStatement() {
  const { locale } = useLocale();
  const copy = getHomeCopy(locale).portal;
  const trackRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const track = trackRef.current;
    if (!track) return;
    const media = gsap.matchMedia();
    media.add(motionQuery.allowed, () => {
      track.dataset.scrub = "true";
      const context = gsap.context(() => {
        const q = gsap.utils.selector(track);
        const timeline = gsap.timeline({
          defaults: { ease: "none" },
          scrollTrigger: { trigger: track, start: "top top", end: "bottom bottom", scrub: 0.6, invalidateOnRefresh: true },
        });
        gsap.set(q("[data-tile]"), { width: 76, height: 76, minHeight: 0, borderRadius: 22 });
        gsap.set(q("[data-word]"), { yPercent: 110, opacity: 0 });
        gsap.set(q("[data-label]"), { opacity: 0, y: 10 });
        gsap.set(q("[data-mark]"), { y: 0, scale: 1 });
        timeline
          .to(q("[data-tile]"), { width: () => window.innerWidth, height: () => window.innerHeight, borderRadius: 0, duration: 1, ease: "power2.inOut" }, 0)
          .to(q("[data-mark]"), { scale: 0.8, y: () => window.innerHeight * 0.22, duration: 1, ease: "power2.inOut" }, 0)
          .to(q("[data-label]"), { opacity: 1, y: 0, duration: 0.3 }, 0.55)
          .to(q("[data-word]"), { yPercent: 0, opacity: 1, duration: 0.5, stagger: 0.04, ease: "power3.out" }, 0.7)
          .to({}, { duration: 0.6 })
          .to(q("[data-tile]"), {
            width: () => Math.min(window.innerWidth * 0.86, 1100),
            height: () => Math.min(window.innerHeight * 0.7, 640),
            borderRadius: 220,
            duration: 0.9,
            ease: "power2.inOut",
          })
          .to(q("[data-tile]"), { opacity: 0, scale: 0.92, duration: 0.5 }, ">-0.1");
      }, track);
      ScrollTrigger.refresh();
      return () => {
        context.revert();
        delete track.dataset.scrub;
      };
    });
    return () => media.revert();
  }, [locale]);

  const words: Array<{ word: string; accent: boolean }> = [];
  copy.statement.forEach((part, index) => {
    for (const word of part.split(/\s+/).filter(Boolean)) words.push({ word, accent: index === 1 });
  });

  return (
    <section aria-label={copy.statement.join("")} className="relative">
      <div ref={trackRef} className="vh-portal-track">
        <div className="vh-portal-stage flex items-center justify-center overflow-hidden py-24">
          <div
            data-tile
            className="relative h-[72vh] min-h-[440px] w-[min(92vw,1100px)] overflow-hidden rounded-[28px] bg-[linear-gradient(160deg,#8f5f96,#764b7c_45%,#5f3a65)] shadow-[0_0_120px_-20px_rgba(154,106,161,0.6)]"
          >
            <div className="vh-portal-dots absolute inset-0" aria-hidden="true" />
            <div className="absolute left-1/2 top-1/2 flex w-[min(90vw,980px)] -translate-x-1/2 -translate-y-[62%] flex-col items-center px-6 text-center">
              <p data-label className="vh-mono text-[11px] text-[#2a1b2c]/70">{copy.label}</p>
              <p className="vh-display mt-6 max-w-[18ch] text-[2.6rem] text-[#1c1a18] sm:text-6xl lg:text-[5.2rem]" aria-hidden="true">
                {words.map(({ word, accent }, index) => (
                  <Fragment key={`${word}-${index}`}>
                    {index > 0 && !/^[.,]/.test(word) ? " " : null}
                    <span className="inline-block overflow-hidden pb-[0.12em] -mb-[0.12em] align-top">
                      <span data-word className={`inline-block ${accent ? "vh-accent !text-[#f7f6f4]" : ""}`}>{word}</span>
                    </span>
                  </Fragment>
                ))}
              </p>
            </div>
            <div data-mark className="absolute left-1/2 top-1/2 -ml-7 -mt-7 flex h-14 w-14 items-center justify-center rounded-[16px] bg-[#1c1a18] shadow-[0_18px_40px_-10px_rgba(0,0,0,0.6)] [transform:translateY(22vh)]">
              <BrandMark size={40} />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
