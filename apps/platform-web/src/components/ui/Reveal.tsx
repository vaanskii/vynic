import { motion, useReducedMotion } from "motion/react";
import { ReactNode } from "react";
import { revealFromBottom, revealTransition } from "../../lib/motion";

type RevealProps = {
  children: ReactNode;
  className?: string;
  delay?: number;
};

export function Reveal({ children, className = "", delay = 0 }: RevealProps) {
  const reduceMotion = useReducedMotion();

  return (
    <motion.div
      className={className}
      initial={reduceMotion ? false : "hidden"}
      whileInView="show"
      viewport={{ once: true, amount: 0.24 }}
      variants={revealFromBottom}
      transition={{ ...revealTransition, delay }}
    >
      {children}
    </motion.div>
  );
}
