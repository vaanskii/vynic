import { useLanguage } from "../contexts/LanguageContext";
import { useWebsiteInfo } from "../contexts/WebsiteInfoContext";
import { useTr } from "../hooks/useTr";
import ImageWithSkeleton from "./ImageWithSkeleton";
import { websiteEmailHref } from "../services/website-info";

export function WebsiteContactEmail({ label }: { label: string }) {
  const { state } = useWebsiteInfo();
  if (state.kind !== "ready") return <WebsiteInfoNotice />;
  if (!state.site.capabilities.profile || !state.site.info.contactEmail)
    return null;
  return (
    <p className="text-gray-400 text-sm">
      {label}
      <a
        href={websiteEmailHref(state.site.info.contactEmail)}
        className="text-[#a89763] hover:text-[#c0ad7b] break-all"
      >
        {state.site.info.contactEmail}
      </a>
    </p>
  );
}

export function WebsiteInfoNotice() {
  const { state, reload } = useWebsiteInfo();
  const tr = useTr();
  if (state.kind === "ready") return null;
  if (state.kind === "loading")
    return (
      <p role="status" className="mt-4 text-sm text-white/60">
        {tr(
          "Loading restaurant information…",
          "რესტორნის ინფორმაცია იტვირთება…",
          "Информация о ресторане загружается…",
        )}
      </p>
    );
  return (
    <div role="alert" className="mt-4 text-sm text-white/70">
      <p>
        {tr(
          "Current restaurant information is unavailable.",
          "რესტორნის მიმდინარე ინფორმაცია ვერ ჩაიტვირთა.",
          "Не удалось загрузить актуальную информацию о ресторане.",
        )}
      </p>
      <button
        type="button"
        onClick={reload}
        className="mt-3 underline text-[#ae895e] focus-visible:outline-2 focus-visible:outline-offset-4"
      >
        {tr("Try again", "ხელახლა ცდა", "Попробовать снова")}
      </button>
    </div>
  );
}

const weekdayNames = {
  en: [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ],
  ka: [
    "ორშაბათი",
    "სამშაბათი",
    "ოთხშაბათი",
    "ხუთშაბათი",
    "პარასკევი",
    "შაბათი",
    "კვირა",
  ],
  ru: [
    "Понедельник",
    "Вторник",
    "Среда",
    "Четверг",
    "Пятница",
    "Суббота",
    "Воскресенье",
  ],
};

export function WebsiteHours() {
  const { state } = useWebsiteInfo();
  const { language } = useLanguage();
  const tr = useTr();
  if (
    state.kind !== "ready" ||
    !state.site.capabilities.hours ||
    !state.site.info.workingHours.length
  )
    return null;
  const hours = state.site.info.workingHours;
  return (
    <dl
      aria-label={tr("Opening hours", "სამუშაო საათები", "Часы работы")}
      className="text-sm text-white/55 space-y-3 font-light tracking-wide"
    >
      {Array.from({ length: 7 }, (_, i) => i + 1).map((day) => {
        const row = hours.find((value) => value.day === day);
        const name = weekdayNames[language][day - 1];
        return (
          <div
            key={day}
            className="flex flex-wrap justify-between gap-x-4 gap-y-1 border-b border-white/5 pb-2"
          >
            <dt>{name}</dt>
            <dd className="text-[#ae895e] whitespace-nowrap">
              {row
                ? `${row.opens} – ${row.closes}`
                : tr("Closed", "დაკეტილია", "Закрыто")}
            </dd>
          </div>
        );
      })}
    </dl>
  );
}

export function WebsiteGallery() {
  const { state } = useWebsiteInfo();
  const { t } = useLanguage();
  if (
    state.kind !== "ready" ||
    !state.site.capabilities.gallery ||
    !state.site.info.gallery.length
  )
    return null;
  return (
    <section
      aria-label={t("atmosphere.gallery")}
      className="max-w-full mx-auto mt-20 md:mt-32 px-4 md:px-8"
    >
      <div className="text-center mb-10 md:mb-12">
        <h4 className="text-[#ae895e] uppercase tracking-[0.4em] text-[10px] md:text-xs font-medium">
          {t("atmosphere.gallery")}
        </h4>
      </div>
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 md:gap-6">
        {state.site.info.gallery.map((photo, i) => (
          <div
            key={`${photo.url}:${i}`}
            className={`aspect-square overflow-hidden border border-white/5 opacity-70 hover:opacity-100 transition-opacity duration-500 ${i % 2 ? "md:translate-y-8" : ""}`}
          >
            <ImageWithSkeleton
              src={photo.url}
              alt={photo.alt}
              width={600}
              height={600}
              loading="lazy"
            />
          </div>
        ))}
      </div>
    </section>
  );
}
