import { useLayoutEffect, useRef, useState } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { ArrowDown } from "@phosphor-icons/react";
import { ProductLaunchMenu } from "../product/ProductLaunchMenu";
import { SplitWords } from "../motion/SplitWords";
import { usePointerDepth } from "../motion/usePointerDepth";
import { Button } from "../ui/Button";
import {
  distance,
  duration,
  gsapEase,
  markHeroIntroPlayed,
  motionQuery,
  shouldPlayHeroIntro,
  stagger,
} from "../../lib/motion";
import { useLocale } from "../../lib/i18n";

gsap.registerPlugin(ScrollTrigger);

export function Hero() {
  const { copy, locale } = useLocale();
  const heroRef = useRef<HTMLElement>(null);
  const copyRef = useRef<HTMLDivElement>(null);
  const mediaRef = useRef<HTMLDivElement>(null);
  const entranceRef = useRef<HTMLDivElement>(null);
  const depthRef = useRef<HTMLDivElement>(null);
  const counterRef = useRef<HTMLDivElement>(null);
  const lightRef = useRef<HTMLDivElement>(null);
  // Decided once per mount so re-renders never replay the opening.
  const [playIntro] = useState(shouldPlayHeroIntro);

  usePointerDepth({ area: heroRef, depth: depthRef, counter: counterRef, light: lightRef });

  // Opening sequence: ~1.3s, nothing is blocked while it runs.
  useLayoutEffect(() => {
    const hero = heroRef.current;
    if (!playIntro || !hero) return;
    let timeline: gsap.core.Timeline | undefined;
    const context = gsap.context(() => {
      const desktop = window.matchMedia(motionQuery.desktop).matches;
      const travel = desktop ? distance.reveal : distance.revealMobile;
      timeline = gsap.timeline({ defaults: { ease: gsapEase.out } });

      timeline
        .fromTo("[data-hero-bg]", { autoAlpha: 0 }, { autoAlpha: 1, duration: 1.2, ease: "power2.out" }, 0)
        .fromTo("[data-hero='eyebrow']", { autoAlpha: 0, y: distance.small }, { autoAlpha: 1, y: 0, duration: 0.6 }, 0.05)
        .fromTo(".vynic-word", { yPercent: 110 }, { yPercent: 0, duration: 0.95, stagger: stagger.tight }, 0.1)
        .fromTo(
          entranceRef.current,
          {
            autoAlpha: 0,
            y: desktop ? distance.media : travel,
            scale: 0.965,
            rotationX: desktop ? 7 : 0,
            transformPerspective: 1600,
            transformOrigin: "50% 100%",
          },
          { autoAlpha: 1, y: 0, scale: 1, rotationX: 0, duration: duration.cinematic },
          0.22,
        )
        .fromTo("[data-hero='body']", { autoAlpha: 0, y: travel }, { autoAlpha: 1, y: 0, duration: duration.reveal }, 0.34)
        .fromTo("[data-hero='cta']", { autoAlpha: 0, y: travel }, { autoAlpha: 1, y: 0, duration: duration.reveal }, 0.42)
        .fromTo(
          "[data-hero='facts'] > *",
          { autoAlpha: 0, y: distance.small },
          { autoAlpha: 1, y: 0, duration: duration.reveal, stagger: 0.06 },
          0.52,
        );
      markHeroIntroPlayed();
    }, hero);
    // Safety net: if frames stall while the page is visible, show the end state.
    const fallback = window.setTimeout(() => {
      if (document.visibilityState === "visible") timeline?.progress(1);
    }, 2500);
    return () => {
      window.clearTimeout(fallback);
      context.revert();
    };
  }, [playIntro]);

  // Leaving the hero: the product recedes and the copy yields (desktop only).
  useLayoutEffect(() => {
    const hero = heroRef.current;
    if (!hero) return;
    const media = gsap.matchMedia();
    media.add(motionQuery.desktop, () => {
      const scroll = { trigger: hero, start: "top top", end: "bottom top", scrub: true };
      gsap.to(mediaRef.current, { y: 70, scale: 0.97, ease: gsapEase.scrub, scrollTrigger: scroll });
      gsap.to(copyRef.current, { y: -32, autoAlpha: 0.35, ease: gsapEase.scrub, scrollTrigger: { ...scroll } });
    });
    return () => media.revert();
  }, []);

  return (
    <section ref={heroRef} id="top" className="relative isolate overflow-hidden border-b border-vynic-border">
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden="true">
        <div data-hero-bg className="vynic-hero-aura absolute inset-0" />
        <div data-hero-bg className="vynic-hero-grid absolute inset-0" />
        <div ref={lightRef} className="vynic-hero-light" />
      </div>
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-[linear-gradient(180deg,transparent,var(--vynic-background))]" />
      <div className="mx-auto grid min-h-[calc(72dvh-56px)] max-w-7xl items-center gap-10 px-4 py-9 sm:px-6 xl:grid-cols-[0.74fr_1.26fr] xl:gap-16 xl:px-8 xl:py-12">
        <div ref={copyRef} className="max-w-2xl">
          <div
            data-hero="eyebrow"
            className="mb-4 flex items-center gap-3 font-vynic-mono text-[11px] font-semibold uppercase tracking-[0.16em] text-vynic-plum"
          >
            <span className="h-2 w-2 rounded-full bg-vynic-plum" />
            {copy.hero.eyebrow}
          </div>
          <h1
            className={`text-4xl font-semibold leading-[1.01] text-vynic-charcoal sm:text-5xl lg:text-[3rem] ${locale === "ka" ? "max-w-[14ch] lg:max-w-[18ch] xl:max-w-[17ch] xl:text-[3.25rem]" : "max-w-[14ch] lg:max-w-[16ch] xl:max-w-[12ch] xl:text-[3.65rem]"}`}
          >
            <SplitWords text={copy.hero.title} />
          </h1>
          <p data-hero="body" className="mt-4 max-w-xl text-base leading-7 text-vynic-muted sm:text-lg">
            {copy.hero.body}
          </p>
          <div data-hero="cta" className="mt-6 flex flex-wrap gap-3">
            <Button href="#contact">{copy.nav.bookDemo}</Button>
            <Button href="#product" variant="secondary" icon={ArrowDown}>
              {copy.hero.seeScreens}
            </Button>
          </div>
          <div data-hero="facts" className="mt-8 grid max-w-lg grid-cols-3 border-y border-vynic-border py-4">
            {["01", "02", "03"].map((number, index) => (
              <div key={number} className="border-r border-vynic-border px-3 first:pl-0 last:border-r-0">
                <p className="font-vynic-mono text-[10px] font-semibold tracking-[0.14em] text-vynic-plum">
                  {number}
                </p>
                <p className="mt-2 text-xs font-semibold text-vynic-charcoal sm:text-sm">{copy.hero.facts[index]}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Layout offset lives on its own wrapper: GSAP owns transforms below it. */}
        <div className="relative mx-auto w-full max-w-[860px] xl:translate-x-5 xl:-translate-y-2">
          <div ref={mediaRef} className="relative">
            <div ref={entranceRef} className="relative">
              <div ref={counterRef} className="pointer-events-none absolute inset-0" aria-hidden="true">
                <div className="absolute -left-10 top-10 hidden h-28 w-28 border border-vynic-border bg-vynic-surface/60 xl:block" />
                <div className="absolute -right-5 bottom-10 hidden h-20 w-20 border border-vynic-border bg-vynic-surface/50 xl:block" />
              </div>
              <div ref={depthRef} className="relative will-change-transform">
                <ProductLaunchMenu className="relative" boot={playIntro} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
