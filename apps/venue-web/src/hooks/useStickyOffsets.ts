import { useState, useEffect } from 'react';

/** Tracks site nav + optional secondary sticky bar heights for scroll offsets. */
export function useStickyOffsets(secondaryRef: React.RefObject<HTMLElement | null>, secondaryActive: boolean) {
  const [navHeight, setNavHeight] = useState(72);
  const [secondaryHeight, setSecondaryHeight] = useState(0);

  useEffect(() => {
    const nav = document.getElementById('site-nav');

    const measure = () => {
      if (nav) setNavHeight(Math.ceil(nav.getBoundingClientRect().height));
      if (secondaryActive && secondaryRef.current) {
        setSecondaryHeight(Math.ceil(secondaryRef.current.getBoundingClientRect().height));
      } else {
        setSecondaryHeight(0);
      }
    };

    measure();
    const raf = requestAnimationFrame(measure);

    const ro = new ResizeObserver(measure);
    if (nav) ro.observe(nav);
    if (secondaryActive && secondaryRef.current) ro.observe(secondaryRef.current);

    window.addEventListener('scroll', measure, { passive: true });
    window.addEventListener('resize', measure);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      window.removeEventListener('scroll', measure);
      window.removeEventListener('resize', measure);
    };
  }, [secondaryRef, secondaryActive]);

  const scrollOffset = navHeight + secondaryHeight + 8;

  return { navHeight, secondaryHeight, scrollOffset };
}
