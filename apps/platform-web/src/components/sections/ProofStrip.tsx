import { motion, useReducedMotion } from "motion/react";
import { getLocalizedContent } from "../../data/siteContent";
import { useLocale } from "../../lib/i18n";
import { revealTransition } from "../../lib/motion";

const listVariants = {
  hidden: {},
  show: {
    transition: {
      staggerChildren: 0.055,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, y: 18 },
  show: {
    opacity: 1,
    y: 0,
    transition: {
      staggerChildren: 0.045,
    },
  },
};

const detailVariants = {
  hidden: { opacity: 0, y: 8 },
  show: { opacity: 1, y: 0 },
};

export function ProofStrip() {
  const reduceMotion = useReducedMotion();
  const { locale, copy } = useLocale();
  const capabilities = getLocalizedContent(locale).capabilities;

  return (
    <section
      className="relative overflow-hidden border-y border-[#403a35] bg-[#22201E] text-[#F7F6F4]"
      aria-label={copy.nav.product}
    >
      <div className="pointer-events-none absolute inset-0 bg-[linear-gradient(90deg,rgba(247,246,244,0.04)_1px,transparent_1px)] bg-[length:14.285%_100%]" />
      <div className="vynic-dark-sweep pointer-events-none absolute inset-y-0 left-0 w-28" />
      <motion.div
        className="relative mx-auto grid max-w-[1360px] grid-cols-2 px-4 py-5 sm:grid-cols-[repeat(auto-fit,minmax(146px,1fr))] sm:px-6 lg:px-8"
        initial={reduceMotion ? false : "hidden"}
        whileInView="show"
        viewport={{ once: true, amount: 0.45 }}
        variants={listVariants}
      >
        {capabilities.map((item) => (
          <motion.article
            key={item.number}
            className="group relative w-full min-h-[116px] last:col-span-2 overflow-hidden border-b border-white/12 px-0 py-2.5 sm:last:col-span-1 sm:border-b-0 sm:border-r sm:border-white/16 sm:px-5 sm:first:pl-0 sm:last:border-r-0 sm:last:pr-0"
            variants={itemVariants}
            whileHover={reduceMotion ? undefined : { y: -5 }}
          >
            <motion.span
              className="block font-vynic-mono text-[10px] font-semibold tracking-[0.14em] text-[#B9A8C4]"
              variants={detailVariants}
              transition={revealTransition}
            >
              {item.number}
            </motion.span>
            <motion.span
              className="mt-1.5 block text-[13px] font-semibold leading-5 text-[#F7F6F4] sm:text-[14px]"
              variants={detailVariants}
              transition={revealTransition}
            >
              {item.label}
            </motion.span>
            <motion.p
              className="mt-3 max-w-none text-[11px] leading-[1.45] text-[#D8D0C9] opacity-[0.72] sm:max-w-[24ch] sm:text-xs"
              variants={detailVariants}
              transition={revealTransition}
            >
              {item.body}
            </motion.p>
            <motion.span
              className="absolute bottom-0 left-0 h-px w-8 bg-[#B9A8C4] duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] motion-safe:transition-[width] group-hover:w-20"
              variants={detailVariants}
              transition={revealTransition}
            />
          </motion.article>
        ))}
      </motion.div>
    </section>
  );
}
