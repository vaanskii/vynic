import { motion, useReducedMotion } from "motion/react";
import { ReactNode, useState } from "react";
import { distance, revealTransition } from "../../lib/motion";

type RevealProps = {
  children: ReactNode;
  className?: string;
  delay?: number;
  id?: string;
};

/** One-time rise-and-fade as the block enters the viewport. */
export function Reveal({ children, className = "", delay = 0, id }: RevealProps) {
  const reduceMotion = useReducedMotion();
  const [travel] = useState(() =>
    window.matchMedia?.("(min-width: 1024px)").matches ? distance.reveal : distance.revealMobile,
  );

  return (
    <motion.div
      id={id}
      className={className}
      initial={reduceMotion ? false : "hidden"}
      whileInView="show"
      viewport={{ once: true, amount: 0.24 }}
      variants={{ hidden: { opacity: 0, y: travel }, show: { opacity: 1, y: 0 } }}
      transition={{ ...revealTransition, delay }}
    >
      {children}
    </motion.div>
  );
}
