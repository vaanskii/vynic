import { motion, useReducedMotion } from "motion/react";
import { useEffect, useState, type ReactNode } from "react";
import { curve } from "../../lib/motion";
import { BrandMark } from "./primitives";

const CURTAIN =
  "pointer-events-none fixed inset-0 z-[70] flex flex-col items-center justify-center bg-[radial-gradient(ellipse_at_50%_40%,#8f5f96,#764b7c_45%,#4a2f4e)]";

// Pages shown so far in this visit; the first one opens without a curtain.
// Counted after commit so StrictMode's double render cannot skew it.
let pagesShown = 0;

/**
 * One page of the site inside the transition. Leaving: the page sinks back
 * while a plum curtain rises over it. Arriving: the curtain carries the new
 * page's name, then lifts away to reveal it.
 */
export function PageFrame({ children, label }: { children: ReactNode; label: string }) {
  const reduce = useReducedMotion();
  // Frozen at mount: later re-renders of this page never bring the curtain back.
  const [arrived] = useState(() => pagesShown > 0);
  const reveal = arrived && !reduce;
  useEffect(() => {
    pagesShown += 1;
  }, []);

  return (
    <motion.div initial={{ opacity: 1 }} animate={{ opacity: 1 }} exit={{ opacity: 1, transition: { duration: reduce ? 0 : 0.8 } }}>
      <motion.div
        initial={reveal ? { opacity: 0, y: 60, scale: 0.98 } : false}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={reduce ? { opacity: 0 } : { opacity: 0.4, scale: 0.94, y: -40, filter: "blur(6px)" }}
        transition={{ duration: 0.8, ease: curve.inOut, delay: reveal ? 0.45 : 0 }}
        style={{ transformOrigin: "50% 30vh" }}
      >
        {children}
      </motion.div>

      {reduce ? null : (
        <>
          {/* Cover: rises from the bottom over the page that is leaving. */}
          <motion.div
            aria-hidden="true"
            className={CURTAIN}
            initial={{ clipPath: "inset(100% 0% 0% 0%)" }}
            animate={{ clipPath: "inset(100% 0% 0% 0%)" }}
            exit={{ clipPath: "inset(0% 0% 0% 0%)" }}
            transition={{ duration: 0.75, ease: curve.inOut }}
          >
            <BrandMark size={56} />
          </motion.div>

          {/* Reveal: holds the arriving page's name, then lifts off the top. */}
          {reveal ? (
            <motion.div
              aria-hidden="true"
              className={CURTAIN}
              initial={{ clipPath: "inset(0% 0% 0% 0%)" }}
              animate={{ clipPath: "inset(0% 0% 100% 0%)" }}
              transition={{ duration: 0.9, ease: curve.inOut, delay: 0.55 }}
            >
              <BrandMark size={56} />
              <motion.span
                className="vh-display mt-6 text-5xl text-[#1c1a18] sm:text-7xl"
                initial={{ opacity: 0, y: 30, rotateX: -60 }}
                animate={{ opacity: 1, y: 0, rotateX: 0 }}
                transition={{ duration: 0.5, ease: curve.out }}
                style={{ transformPerspective: 800 }}
              >
                {label}
              </motion.span>
            </motion.div>
          ) : null}
        </>
      )}
    </motion.div>
  );
}
