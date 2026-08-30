import { motion, useReducedMotion } from "motion/react";
import { ArrowDown } from "@phosphor-icons/react";
import { ProductLaunchMenu } from "../product/ProductLaunchMenu";
import { Button } from "../ui/Button";
import { revealFromBottom, revealTransition, staggerParent } from "../../lib/motion";
import { useLocale } from "../../lib/i18n";

export function Hero() {
  const reduceMotion = useReducedMotion();
  const { copy, locale } = useLocale();

  return (
    <section id="top" className="relative overflow-hidden border-b border-vynic-border">
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-24 bg-[linear-gradient(180deg,transparent,var(--vynic-background))]" />
      <div className="mx-auto grid min-h-[calc(72dvh-56px)] max-w-7xl items-center gap-10 px-4 py-9 sm:px-6 xl:grid-cols-[0.74fr_1.26fr] xl:gap-16 xl:px-8 xl:py-12">
        <motion.div
          initial={reduceMotion ? false : "hidden"}
          animate="show"
          variants={staggerParent}
          className="max-w-2xl"
        >
          <motion.div
            variants={revealFromBottom}
            transition={revealTransition}
            className="mb-4 flex items-center gap-3 font-vynic-mono text-[11px] font-semibold uppercase tracking-[0.16em] text-vynic-plum"
          >
            <span className="vynic-soft-pulse h-2 w-2 rounded-full bg-vynic-plum" />
            {copy.hero.eyebrow}
          </motion.div>
          <motion.h1
            variants={revealFromBottom}
            transition={revealTransition}
            className={`text-4xl font-semibold leading-[1.01] text-vynic-charcoal sm:text-5xl lg:text-[3rem] ${locale === "ka" ? "max-w-[14ch] lg:max-w-[18ch] xl:max-w-[17ch] xl:text-[3.25rem]" : "max-w-[14ch] lg:max-w-[16ch] xl:max-w-[12ch] xl:text-[3.65rem]"}`}
          >
            {copy.hero.title}
          </motion.h1>
          <motion.p
            variants={revealFromBottom}
            transition={revealTransition}
            className="mt-4 max-w-xl text-base leading-7 text-vynic-muted sm:text-lg"
          >
            {copy.hero.body}
          </motion.p>
          <motion.div
            variants={revealFromBottom}
            transition={revealTransition}
            className="mt-6 flex flex-wrap gap-3"
          >
            <Button href="#contact">{copy.nav.bookDemo}</Button>
            <Button href="#product" variant="secondary" icon={ArrowDown}>
              {copy.hero.seeScreens}
            </Button>
          </motion.div>
          <motion.div
            variants={revealFromBottom}
            transition={revealTransition}
            className="mt-8 grid max-w-lg grid-cols-3 border-y border-vynic-border py-4"
          >
            {[
              ["01", "Floor first"],
              ["02", "Offline ready"],
              ["03", "GEL native"],
            ].map(([number], index) => (
              <div key={number} className="border-r border-vynic-border px-3 first:pl-0 last:border-r-0">
                <p className="font-vynic-mono text-[10px] font-semibold tracking-[0.14em] text-vynic-plum">
                  {number}
                </p>
                <p className="mt-2 text-xs font-semibold text-vynic-charcoal sm:text-sm">{copy.hero.facts[index]}</p>
              </div>
            ))}
          </motion.div>
        </motion.div>

        <motion.div
          initial={reduceMotion ? false : { opacity: 0, y: 34, scale: 0.985 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          whileHover={reduceMotion ? undefined : { y: -8, rotate: -0.35 }}
          transition={{ ...revealTransition, delay: reduceMotion ? 0 : 0.18 }}
          className="relative mx-auto w-full max-w-[860px] xl:translate-x-5 xl:-translate-y-2"
        >
          <div className="absolute -left-10 top-10 hidden h-28 w-28 border border-vynic-border bg-vynic-surface/60 xl:block" />
          <div className="absolute -right-5 bottom-10 hidden h-20 w-20 border border-vynic-border bg-vynic-surface/50 xl:block" />
          <ProductLaunchMenu className="relative" />
        </motion.div>
      </div>
    </section>
  );
}
