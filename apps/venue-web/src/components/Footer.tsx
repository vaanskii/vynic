import { useParams } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';
import { useTr } from '../hooks/useTr';

const Footer = () => {
  const { t, language } = useLanguage();
  const tr = useTr();
  const params = useParams<{ lang: string }>();
  const currentLang = params.lang || language;

  return (
    <footer className="pt-24 pb-12 px-6 lg:px-8 border-t border-white/5 bg-[#030303] relative z-40">
      <div className="max-w-7xl mx-auto">

        {/* ── Main grid ────────────────────────────────────────────────── */}
        <div className="grid grid-cols-1 md:grid-cols-12 gap-12 lg:gap-20 mb-20">

          {/* Brand column */}
          <div className="md:col-span-4">
            <div className="flex items-center gap-4 mb-6">
              <img
                src="/black-logo.png"
                alt="Vankisi Logo"
                className="h-12 w-auto"
              />
              <span className="text-xl font-medium tracking-[0.3em] uppercase text-white/90">
                VANKISI
              </span>
            </div>
            <p className="text-white/35 text-sm leading-loose font-light">
              {tr(
                'Where hospitality is an art form. The finest Georgian flavours and premium gastronomic experience in one refined space.',
                'სადაც სტუმართმოყვარეობა ხელოვნებაა. საუკეთესო ქართული გემოები და პრემიუმ ხარისხის გასტრონომიული გამოცდილება ერთ დახვეწილ სივრცეში.',
                'Где гостеприимство — это искусство. Лучшие грузинские вкусы и премиальный гастрономический опыт в одном изысканном пространстве.',
              )}
            </p>
          </div>

          {/* Hours column */}
          <div className="md:col-span-3">
            <h5 className="text-white/30 font-medium uppercase tracking-[0.3em] text-[10px] mb-8">
              {tr('Opening Hours', 'სამუშაო საათები', 'Часы работы')}
            </h5>
            <div className="text-sm text-white/55 space-y-4 font-light tracking-wide">
              <p className="flex justify-between border-b border-white/5 pb-3">
                <span>{tr('Every day', 'ყოველდღე', 'Каждый день')}</span>
                <span className="text-[#ae895e]">11:00 – 00:00</span>
              </p>
            </div>
          </div>

          {/* Contact column */}
          <div className="md:col-span-3">
            <h5 className="text-white/30 font-medium uppercase tracking-[0.3em] text-[10px] mb-8">
              {t('contact.getInTouch')}
            </h5>
            <div className="text-sm text-white/55 space-y-5 font-light">
              <a
                href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent('Georgia Batumi Pushkini ST N51')}`}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-start gap-4 hover:text-[#ae895e] transition-colors group"
              >
                <svg className="w-4 h-4 text-[#ae895e] mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
                <span className="tracking-wide leading-relaxed whitespace-pre-line">
                  {t('contact.address.value')}
                </span>
              </a>
              <a
                href="tel:+995000000000"
                className="flex items-center gap-4 hover:text-[#ae895e] transition-colors"
              >
                <svg className="w-4 h-4 text-[#ae895e] flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                </svg>
                <span className="tracking-wide">+995 599 98 93 76</span>
              </a>
            </div>
          </div>

          {/* Socials column */}
          <div className="md:col-span-2">
            <h5 className="text-white/30 font-medium uppercase tracking-[0.3em] text-[10px] mb-8">
              {t('contact.followUs')}
            </h5>
            <div className="flex gap-3">
              {/* Instagram */}
              <a
                href="https://www.instagram.com/restaurant_vankisi/"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Instagram"
                className="w-11 h-11 rounded-full border border-white/10 flex items-center justify-center text-white/50 hover:border-[#ae895e] hover:text-[#ae895e] transition-all duration-300"
              >
                <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/>
                </svg>
              </a>

              {/* Facebook */}
              <a
                href="https://www.facebook.com/profile.php?id=61576331520099"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="Facebook"
                className="w-11 h-11 rounded-full border border-white/10 flex items-center justify-center text-white/50 hover:border-[#ae895e] hover:text-[#ae895e] transition-all duration-300"
              >
                <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
                </svg>
              </a>

              {/* TikTok */}
              <a
                href="https://tiktok.com"
                target="_blank"
                rel="noopener noreferrer"
                aria-label="TikTok"
                className="w-11 h-11 rounded-full border border-white/10 flex items-center justify-center text-white/50 hover:border-[#ae895e] hover:text-[#ae895e] transition-all duration-300"
              >
                <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-5.2 1.74 2.89 2.89 0 0 1 2.31-4.64 2.93 2.93 0 0 1 .88.13V9.4a6.84 6.84 0 0 0-1-.05A6.33 6.33 0 0 0 5 20.1a6.34 6.34 0 0 0 10.86-4.43v-7a8.16 8.16 0 0 0 4.77 1.52v-3.4a4.85 4.85 0 0 1-1-.1z"/>
                </svg>
              </a>
            </div>

            {/* Quick nav links */}
            <div className="mt-8 space-y-3 text-[10px] uppercase tracking-[0.2em]">
              <a href={`/${currentLang}/about`} className="block text-white/30 hover:text-[#ae895e] transition-colors">
                {t('nav.about')}
              </a>
              <a href={`/${currentLang}/menu`} className="block text-white/30 hover:text-[#ae895e] transition-colors">
                {t('nav.menu')}
              </a>
              <button 
                onClick={() => {
                  if (window.location.pathname !== `/${currentLang}`) {
                    window.location.href = `/${currentLang}`;
                    setTimeout(() => document.getElementById('reservation-section')?.scrollIntoView({ behavior: 'smooth' }), 500);
                  } else {
                    document.getElementById('reservation-section')?.scrollIntoView({ behavior: 'smooth' });
                  }
                }}
                className="block text-white/30 hover:text-[#ae895e] transition-colors cursor-pointer text-left w-full"
              >
                {t('nav.reservations')}
              </button>
              <a href={`/${currentLang}/contact`} className="block text-white/30 hover:text-[#ae895e] transition-colors">
                {t('nav.contact')}
              </a>
            </div>
          </div>

        </div>

        {/* ── Bottom bar ──────────────────────────────────────────────── */}
        <div className="pt-8 border-t border-white/5 flex flex-col md:flex-row justify-between items-center gap-5 text-[10px] uppercase tracking-[0.2em] text-white/25 text-center">
          <p>{t('contact.copyright')}</p>
          <div className="flex flex-wrap justify-center gap-x-6 gap-y-3">
            <a href="#" className="hover:text-[#ae895e] transition-colors">{t('contact.privacyPolicy')}</a>
            <a href="#" className="hover:text-[#ae895e] transition-colors">{t('contact.termsOfService')}</a>
            <a href="#" className="hover:text-[#ae895e] transition-colors">{t('contact.accessibility')}</a>
          </div>
        </div>

      </div>
    </footer>
  );
};

export default Footer;