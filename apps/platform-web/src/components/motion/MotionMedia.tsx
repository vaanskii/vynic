import { useLayoutEffect, useRef, type ReactNode } from "react";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { distance, duration, gsapEase, motionQuery } from "../../lib/motion";

gsap.registerPlugin(ScrollTrigger);

/**
 * Large product media that settles into place as it scrolls in: a slightly
 * inset, smaller frame opens to full size (desktop, scrubbed by native
 * scroll). Small screens get a short one-time rise; reduced motion gets the
 * media as-is.
 */
export function MotionMedia({ children, className = "" }: { children: ReactNode; className?: string }) {
  const ref = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const media = gsap.matchMedia();
    media.add(motionQuery.desktop, () => {
      gsap.fromTo(
        element,
        { scale: 0.93, y: distance.media, clipPath: "inset(4% 5% 0% 5% round 20px)" },
        {
          scale: 1,
          y: 0,
          // Ends outside the box so the media's own shadow is never clipped.
          clipPath: "inset(-12% -12% -12% -12% round 20px)",
          ease: gsapEase.scrub,
          scrollTrigger: { trigger: element, start: "top 92%", end: "top 38%", scrub: 0.5 },
        },
      );
    });
    media.add(motionQuery.compact, () => {
      gsap.fromTo(
        element,
        { autoAlpha: 0, y: distance.revealMobile },
        {
          autoAlpha: 1,
          y: 0,
          duration: duration.reveal,
          ease: gsapEase.out,
          scrollTrigger: { trigger: element, start: "top 88%", once: true },
        },
      );
    });
    return () => media.revert();
  }, []);

  return (
    <div ref={ref} className={`origin-top ${className}`}>
      {children}
    </div>
  );
}
