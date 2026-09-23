import { useEffect } from "react";
import { useLocation } from "react-router-dom";
import { Footer } from "../components/layout/Footer";
import { Navbar } from "../components/layout/Navbar";
import { DemoForm } from "../components/sections/DemoForm";
import { FloorPlanSection } from "../components/sections/FloorPlanSection";
import { Hero } from "../components/sections/Hero";
import { LocalFitSection } from "../components/sections/LocalFitSection";
import { ManagerSection } from "../components/sections/ManagerSection";
import { ProductTour } from "../components/sections/ProductTour";
import { ProofStrip } from "../components/sections/ProofStrip";
import { ReservationStory } from "../components/sections/ReservationStory";
import { ScrollProgress } from "../components/ui/ScrollProgress";

export function HomePage() {
  const { hash } = useLocation();
  // In-app redirects such as /features land on a section; the browser only
  // scrolls to a fragment by itself on a full page load.
  useEffect(() => {
    if (hash) document.getElementById(hash.slice(1))?.scrollIntoView?.();
  }, [hash]);
  return (
    <div className="min-h-[100dvh] bg-vynic-background text-vynic-charcoal">
      <ScrollProgress />
      <Navbar />
      <main>
        <Hero />
        <ProofStrip />
        <FloorPlanSection />
        <ProductTour />
        <ReservationStory />
        <ManagerSection />
        <LocalFitSection />
        <DemoForm />
      </main>
      <Footer />
    </div>
  );
}
