/**
 * Vynic public-site motion tokens. Every duration, curve, distance and
 * strength on the marketing page comes from here (GSAP and Motion) or from the
 * matching `--motion-*` CSS custom properties in `styles/index.css`.
 *
 * Language: calm precision. Long-tail settles, no overshoot, short travel,
 * depth from scale and light rather than rotation.
 */

/** Seconds. */
export const duration = {
  /** Hover, press, focus, small state changes. */
  fast: 0.18,
  /** Menus, tabs, secondary fades. */
  base: 0.32,
  /** Section and card reveals. */
  reveal: 0.62,
  /** Hero and product-media entrances. */
  cinematic: 1.05,
} as const;

/** Cubic-bezier curves for Motion / CSS. */
export const curve = {
  /** House settle: fast launch, long quiet tail (≈ expo.out). */
  out: [0.16, 1, 0.3, 1] as const,
  /** Symmetric moves and crossfades. */
  inOut: [0.65, 0, 0.35, 1] as const,
};

/** GSAP ease names matching `curve`. */
export const gsapEase = {
  out: "expo.out",
  settle: "power3.out",
  inOut: "power2.inOut",
  /** Scroll-scrubbed segments: progress is already user-driven. */
  scrub: "none",
} as const;

/** Pixels of travel for entrances. */
export const distance = {
  small: 10,
  reveal: 24,
  revealMobile: 14,
  media: 40,
} as const;

export const stagger = {
  /** Words inside one headline. Keep items × tight ≤ ~0.4s. */
  tight: 0.035,
  /** Sibling blocks in one group. */
  base: 0.07,
} as const;

/** Pointer-follow strength in the hero (fine pointers only). */
export const pointer = {
  /** Max device tilt in degrees. */
  tilt: 3,
  /** Max parallax shift of the device in px. */
  shift: 10,
  /** Seconds the follower takes to catch the pointer. */
  lag: 0.9,
} as const;

/** Media queries shared by every GSAP `matchMedia` block. */
export const motionQuery = {
  allowed: "(prefers-reduced-motion: no-preference)",
  desktop: "(min-width: 1024px) and (prefers-reduced-motion: no-preference)",
  compact: "(max-width: 1023px) and (prefers-reduced-motion: no-preference)",
  finePointer:
    "(min-width: 1024px) and (hover: hover) and (pointer: fine) and (prefers-reduced-motion: no-preference)",
} as const;

export const revealTransition = {
  duration: duration.reveal,
  ease: curve.out,
};

export const revealFromBottom = {
  hidden: { opacity: 0, y: distance.reveal },
  show: { opacity: 1, y: 0 },
};

export const staggerParent = {
  hidden: {},
  show: {
    transition: {
      staggerChildren: stagger.base,
    },
  },
};

const INTRO_KEY = "vynic-site-intro";

/**
 * The full opening sequence plays once per browser session: the first
 * impression gets the choreography, while returning from /login, switching
 * language or refreshing shows the page immediately. It is also skipped when
 * the visit starts away from the hero (a #section link or restored scroll).
 */
export function shouldPlayHeroIntro(): boolean {
  if (typeof window === "undefined") return false;
  if (!window.matchMedia?.(motionQuery.allowed).matches) return false;
  if (window.location.hash || window.scrollY > 40) return false;
  try {
    return window.sessionStorage.getItem(INTRO_KEY) !== "played";
  } catch {
    return true;
  }
}

export function markHeroIntroPlayed() {
  try {
    window.sessionStorage.setItem(INTRO_KEY, "played");
  } catch {
    // Storage can be blocked; the intro then simply plays again next visit.
  }
}
