import { FloorEditorDemo } from "./FloorEditorDemo";
import { Reveal } from "../ui/Reveal";
import { SectionHeading } from "../ui/SectionHeading";
import { useLocale } from "../../lib/i18n";

export function FloorPlanSection() {
  const { copy } = useLocale();
  return (
    <section id="floor-plan" className="px-4 py-20 sm:px-6 lg:px-8 lg:py-28">
      <div className="mx-auto w-full max-w-[1600px]">
        <SectionHeading
          title={copy.floor.title}
          body={copy.floor.body}
        />
        <Reveal className="mt-12">
          <FloorEditorDemo />
        </Reveal>
      </div>
    </section>
  );
}
