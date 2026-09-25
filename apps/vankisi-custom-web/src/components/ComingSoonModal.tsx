import { createPortal } from 'react-dom';
import { useEffect } from 'react';
import { useLanguage, LANGUAGES, type Language } from '../contexts/LanguageContext';

const LANG_LABEL: Record<Language, string> = { en: 'EN', ka: 'KA', ru: 'RU' };

const COPY: Record<
  Language,
  { title: string; message: string; note: string }
> = {
  en: {
    title: 'Coming Soon!',
    message:
      'Our website is currently under construction. We are preparing something special and will be back online soon.',
    note: 'Thank you for your patience.',
  },
  
  ka: {
    title: 'მალე!',
    message:
      'ჩვენი ვებგვერდი ამჟამად მზადების პროცესშია. მალე განსაკუთრებული სიახლეებით დაგიბრუნდებით.',
    note: 'გმადლობთ მოთმინებისთვის.',
  },
  
  ru: {
    title: 'Скоро!',
    message:
      'Наш сайт находится в разработке. Мы готовим для вас что-то особенное и скоро вернёмся онлайн.',
    note: 'Спасибо за ваше терпение.',
  },
};

export default function ComingSoonModal() {
  const { language, setLanguage } = useLanguage();
  const copy = COPY[language];

  useEffect(() => {
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = '';
    };
  }, []);

  return createPortal(
    <div
      className="fixed inset-0 z-[200] flex items-center justify-center p-4 sm:p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="coming-soon-title"
    >
      <div className="absolute inset-0 bg-[#050505]/90" />

      <div className="relative w-full max-w-md border border-white/10 bg-[#0a0a0a] p-8 shadow-2xl sm:p-10">
        <div className="absolute top-0 left-0 w-full h-[1px] bg-gradient-to-r from-transparent via-[#ae895e]/40 to-transparent" />
        <div className="absolute bottom-0 left-0 w-full h-[1px] bg-gradient-to-r from-transparent via-[#ae895e]/40 to-transparent" />

        <p className="text-[10px] uppercase tracking-[0.4em] text-[#ae895e] mb-4 text-center">
          Vankisi
        </p>

        <h2
          id="coming-soon-title"
          className="text-2xl sm:text-3xl font-light text-white text-center mb-6 tracking-wide"
        >
          {copy.title}
        </h2>

        <p className="text-sm sm:text-base font-light text-white/70 text-center leading-relaxed mb-6">
          {copy.message}
        </p>

        <p className="text-[10px] uppercase tracking-[0.25em] text-white/40 text-center mb-8">
          {copy.note}
        </p>

        <div className="flex items-center justify-center gap-2 border-t border-white/5 pt-6">
          {LANGUAGES.map(lng => (
            <button
              key={lng}
              type="button"
              onClick={() => setLanguage(lng)}
              className={`px-3 py-1.5 text-[10px] uppercase tracking-[0.2em] transition-colors ${
                language === lng
                  ? 'bg-[#ae895e] text-[#050505]'
                  : 'border border-white/10 text-white/50 hover:text-[#ae895e] hover:border-[#ae895e]/40'
              }`}
            >
              {LANG_LABEL[lng]}
            </button>
          ))}
        </div>
      </div>
    </div>,
    document.body,
  );
}
