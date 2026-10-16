import { AnimatePresence, motion, useReducedMotion, useScroll, useSpring } from "motion/react";
import { useEffect } from "react";
import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import { HomeFooter } from "../components/home/HomeContact";
import { HomeNav } from "../components/home/HomeNav";
import { PageFrame } from "../components/home/PageFrame";
import { RibbonField } from "../components/home/RibbonField";
import { getSiteCopy } from "../components/home/siteCopy";
import { useLocale } from "../lib/i18n";
import { HomePage } from "./HomePage";
import { FloorPage, ManagerPage, PosPage, ReservationsPage } from "./SitePages";
import "../components/home/home.css";

/**
 * The public product site: one persistent stage (ribbon light, navigation,
 * footer) and pages that hand over to each other through a plum curtain.
 * Mounted under /en/* and /ka/*.
 */
export function MarketingSite() {
  const location = useLocation();
  const { locale } = useLocale();
  const pages = getSiteCopy(locale).pages;
  const segment = location.pathname.split("/").filter(Boolean)[1] ?? "";
  const label = Object.values(pages).find((page) => page.path === segment)?.nav ?? "Vynic";

  // A charcoal stage: match the canvas behind overscroll.
  useEffect(() => {
    const root = document.documentElement;
    const previous = root.style.background;
    root.style.background = "#1c1a18";
    return () => {
      root.style.background = previous;
    };
  }, []);

  return (
    <div className="vh">
      <RibbonField />
      <ScrollLine />
      <HomeNav />
      <AnimatePresence
        mode="wait"
        initial={false}
        onExitComplete={() => {
          if (!window.location.hash) window.scrollTo({ top: 0, behavior: "instant" as ScrollBehavior });
        }}
      >
        <PageFrame key={location.pathname} label={label}>
          <main>
            <Routes location={location}>
              <Route index element={<HomePage />} />
              <Route path={pages.pos.path} element={<PosPage />} />
              <Route path={pages.manager.path} element={<ManagerPage />} />
              <Route path={pages.floor.path} element={<FloorPage />} />
              <Route path={pages.reservations.path} element={<ReservationsPage />} />
              <Route path="*" element={<Navigate to=".." replace />} />
            </Routes>
          </main>
          <HomeFooter />
        </PageFrame>
      </AnimatePresence>
    </div>
  );
}

/** A hairline of plum light across the top that tracks reading progress. */
function ScrollLine() {
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll();
  const scaleX = useSpring(scrollYProgress, { stiffness: 120, damping: 30 });
  if (reduce) return null;
  return (
    <motion.div
      aria-hidden="true"
      className="fixed inset-x-0 top-0 z-50 h-[2px] origin-left bg-[linear-gradient(90deg,#764b7c,#d8b6de)] shadow-[0_0_10px_rgba(216,182,222,0.8)]"
      style={{ scaleX }}
    />
  );
}
