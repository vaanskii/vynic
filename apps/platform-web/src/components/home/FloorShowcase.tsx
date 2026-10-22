import { useLocale } from "../../lib/i18n";
import { MotionMedia } from "../motion/MotionMedia";
import { FloorEditorDemo } from "../sections/FloorEditorDemo";
import { getHomeCopy } from "./homeCopy";
import { SectionOpen } from "./primitives";

/** The real, working floor editor, lit from behind and opened by scroll. */
export function FloorShowcase({ bare = false }: { bare?: boolean }) {
  const { copy, locale } = useLocale();
  const home = getHomeCopy(locale);
  return (
    <section className="relative px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-[1320px]">
        {bare ? null : <SectionOpen kicker={home.floor.kicker} title={home.floor.title} body={copy.floor.body} />}
        <MotionMedia className={`relative ${bare ? "" : "mt-14"}`}>
          <div aria-hidden="true" className="absolute -inset-x-10 -inset-y-12 -z-10 rounded-[48px] bg-[radial-gradient(ellipse_at_center,rgba(154,106,161,0.32),transparent_68%)] blur-2xl" />
          <div className="rounded-[20px] border border-[var(--vh-line-strong)] bg-[var(--vh-panel)] p-1.5 shadow-[0_60px_120px_-40px_rgba(0,0,0,0.8)] sm:p-2 [&>div]:!mt-0">
            <FloorEditorDemo />
          </div>
        </MotionMedia>
      </div>
    </section>
  );
}
