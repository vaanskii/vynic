import { useEffect } from "react";
import { useLocation } from "react-router-dom";
import { ExploreRail } from "../components/home/ExploreRail";
import { HomeContact } from "../components/home/HomeContact";
import { HomeHero } from "../components/home/HomeHero";
import { ManagerApp } from "../components/home/ManagerApp";
import { PortalStatement } from "../components/home/PortalStatement";
import { ShiftScene } from "../components/home/ShiftScene";

/**
 * Home is the short version: the live hero, one cinematic shift, the swipeable
 * Manager phone, doors to the product pages, the statement and the demo request.
 */
export function HomePage() {
  const { hash } = useLocation();
  // In-app redirects such as /features land on a section; the browser only
  // scrolls to a fragment by itself on a full page load.
  useEffect(() => {
    if (hash) document.getElementById(hash.slice(1))?.scrollIntoView?.();
  }, [hash]);

  return (
    <>
      <HomeHero />
      <ShiftScene />
      <ManagerApp />
      <ExploreRail />
      <PortalStatement />
      <HomeContact />
    </>
  );
}
