import screenFloor from "../assets/screen-pos-floor-live.png";
import { BookingDemo } from "../components/home/BookingDemo";
import { DailyView } from "../components/home/DailyView";
import { FloorScene } from "../components/home/FloorScene";
import { FloorShowcase } from "../components/home/FloorShowcase";
import { NextPage, PageHero, Tablet } from "../components/home/kinetic";
import { LocalNumbers } from "../components/home/LocalNumbers";
import { ManagerApp } from "../components/home/ManagerApp";
import { ManagerOrbit } from "../components/home/ManagerOrbit";
import { Reliability } from "../components/home/Reliability";
import { ReservationFlow } from "../components/home/ReservationFlow";
import { ScreensTour } from "../components/home/ScreensTour";
import { ScrollMarquee, ScrollWords } from "../components/home/ScrollWords";
import { ServiceFlow } from "../components/home/ServiceFlow";
import { getSiteCopy, PAGE_ORDER, type PageKey } from "../components/home/siteCopy";
import { SurfacesRail } from "../components/home/SurfacesRail";
import { localeHref, useLocale } from "../lib/i18n";

type Key = Exclude<PageKey, "home">;

function usePage(key: Key) {
  const { locale } = useLocale();
  const copy = getSiteCopy(locale);
  const nextKey = PAGE_ORDER[(PAGE_ORDER.indexOf(key) + 1) % PAGE_ORDER.length];
  return {
    page: copy.pages[key],
    next: { label: copy.next, title: copy.pages[nextKey].nav, to: `${localeHref(locale)}/${copy.pages[nextKey].path}` },
  };
}

export function PosPage() {
  const { page, next } = usePage("pos");
  return (
    <>
      <PageHero
        kicker={page.kicker}
        title={page.title}
        body={page.body}
        visual={
          <Tablet>
            <img src={screenFloor} alt="Vynic POS live floor" className="aspect-[3456/2234] w-full object-cover" draggable={false} />
          </Tablet>
        }
      />
      <ScreensTour />
      <ScrollWords />
      <ServiceFlow />
      <ScrollMarquee />
      <Reliability />
      <LocalNumbers />
      <NextPage {...next} />
    </>
  );
}

export function ManagerPage() {
  const { page, next } = usePage("manager");
  return (
    <>
      <PageHero kicker={page.kicker} title={page.title} body={page.body} visual={<ManagerOrbit />} />
      <ManagerApp bare />
      <DailyView />
      <NextPage {...next} />
    </>
  );
}

export function FloorPage() {
  const { page, next } = usePage("floor");
  return (
    <>
      <PageHero kicker={page.kicker} title={page.title} body={page.body} />
      <FloorScene />
      <FloorShowcase bare />
      <SurfacesRail />
      <NextPage {...next} />
    </>
  );
}

export function ReservationsPage() {
  const { page, next } = usePage("reservations");
  return (
    <>
      <PageHero kicker={page.kicker} title={page.title} body={page.body} />
      <BookingDemo />
      <ReservationFlow bare />
      <NextPage {...next} />
    </>
  );
}
