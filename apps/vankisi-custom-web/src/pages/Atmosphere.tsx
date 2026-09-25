import { useNavigate } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';
import Footer from '../components/Footer';
import { useState, useRef, useEffect } from 'react';
import atmosphere from '../assets/restaurant/athmosphere3.jpg';
import bararea from '../assets/restaurant/bararea.jpg';
import atmosphere2 from '../assets/restaurant/athmosphere2.jpg';
import specialevent from '../assets/restaurant/specialevent.jpg';
import culinarydetail from '../assets/restaurant/culinarydetail.jpg';
import ImageWithSkeleton from '../components/ImageWithSkeleton';

const AnimatedSection = ({ children, className = '', delay = 0 }: any) => {
  const [isVisible, setIsVisible] = useState(false);
  const domRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          setIsVisible(true);
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });

    if (domRef.current) observer.observe(domRef.current);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={domRef}
      className={`transition-all duration-1000 transform ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'} ${className}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </div>
  );
};

const Atmosphere = () => {
  const { t, language } = useLanguage();
  const navigate = useNavigate();

  const handleNavClick = (path: string) => {
    navigate(`/${language}/${path}`);
  };

  const titleEn = "The Atmosphere";
  const titleKa = "განსაკუთრებული გარემო";
  const title = language === 'ka' ? titleKa : titleEn;
  const titleParts = title.split(' ');

  return (
    <>
      <div className="pt-24 pb-16 md:pt-32 md:pb-32 min-h-screen bg-[#050505] relative overflow-hidden">

        <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8 mb-16 md:mb-24 text-center pt-8 md:pt-0">
          <span className="text-[#ae895e] uppercase tracking-[0.4em] text-[10px] md:text-xs font-medium block mb-4 md:mb-6 animate-fade-up-init">{t('atmosphere.subtitle')}</span>
          <h1 className="text-4xl md:text-5xl lg:text-7xl font-light mb-6 md:mb-8 tracking-wide text-white/95 animate-fade-up-init" style={{ animationDelay: '100ms' }}>
            {titleParts.length > 0 ? titleParts[0] : title} <span className="italic font-serif text-[#ae895e]">{titleParts.slice(1).join(' ') || ''}</span>
          </h1>
          <p className="text-white/60 max-w-3xl mx-auto leading-relaxed md:leading-loose font-light text-base md:text-lg animate-fade-up-init" style={{ animationDelay: '200ms' }}>
            {t('atmosphere.intro')}
          </p>
        </div>

        <div className="space-y-20 md:space-y-32">

          {/* Section 1: Main Dining */}
          <div className="max-w-7xl mx-auto px-6 md:px-8">
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-20 items-center">
              <AnimatedSection className="lg:col-span-7 relative">
                <div className="aspect-[4/3] overflow-hidden border border-white/5 relative group">
                  <ImageWithSkeleton
                    src={atmosphere}
                    alt="Main Dining Room"
                    className="transition-transform duration-1000 group-hover:scale-105 opacity-80"
                  />
                  <div className="absolute inset-0 bg-black/20 group-hover:bg-black/0 transition-colors duration-700 pointer-events-none"></div>
                </div>
                {/* Decorative element hidden on mobile */}
                <div className="hidden md:block absolute -bottom-6 -left-6 w-32 h-32 border-l border-b border-[#ae895e]/30 z-[-1]"></div>
              </AnimatedSection>

              <AnimatedSection className="lg:col-span-5" delay={200}>
                <span className="text-[#ae895e] text-[10px] md:text-xs uppercase tracking-[0.3em] font-bold mb-3 md:mb-4 block">01</span>
                <h3 className="text-3xl md:text-4xl font-light text-white/95 mb-4 md:mb-6 tracking-wide leading-tight">
                  {t('atmosphere.sec1Title')}
                </h3>
                <p className="text-white/60 leading-relaxed md:leading-loose font-light text-sm md:text-lg">
                  {t('atmosphere.sec1Desc')}
                </p>
              </AnimatedSection>
            </div>
          </div>

          {/* Section 2: VIP / Private (Alternating Layout) */}
          <div className="max-w-7xl mx-auto px-6 md:px-8">
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-20 items-center">
              <AnimatedSection className="lg:col-span-5 order-2 lg:order-1" delay={200}>
                <span className="text-[#ae895e] text-[10px] md:text-xs uppercase tracking-[0.3em] font-bold mb-3 md:mb-4 block">02</span>
                <h3 className="text-3xl md:text-4xl font-light text-white/95 mb-4 md:mb-6 tracking-wide leading-tight">
                  {t('atmosphere.sec2Title')}
                </h3>
                <p className="text-white/60 leading-relaxed md:leading-loose font-light text-sm md:text-lg">
                  {t('atmosphere.sec2Desc')}
                </p>
              </AnimatedSection>

              <AnimatedSection className="lg:col-span-7 order-1 lg:order-2 relative">
                <div className="aspect-[16/9] overflow-hidden border border-white/5 relative group">
                  <ImageWithSkeleton
                    src="https://images.unsplash.com/photo-1559339352-11d035aa65de?q=80&w=1200&auto=format&fit=crop"
                    alt="VIP Space"
                    className="transition-transform duration-1000 group-hover:scale-105 opacity-80"
                  />
                  <div className="absolute inset-0 bg-black/20 group-hover:bg-black/0 transition-colors duration-700 pointer-events-none"></div>
                </div>
                {/* Decorative element hidden on mobile */}
                <div className="hidden md:block absolute -top-6 -right-6 w-32 h-32 border-r border-t border-[#ae895e]/30 z-[-1]"></div>
              </AnimatedSection>
            </div>
          </div>

          {/* Section 3: Lounge / Bar (Full width parallax style) */}
          <AnimatedSection className="relative py-24 md:py-40 border-y border-white/5 overflow-hidden">
            <div className="absolute inset-0 z-0">
              <div className="absolute inset-0 bg-[#050505]/80 z-10" />
              <ImageWithSkeleton
                src="https://images.unsplash.com/photo-1572116469696-31de0f17cc34?q=80&w=2000&auto=format&fit=crop"
                alt="Lounge Bar"
                className="opacity-40 scale-105"
              />
            </div>
            <div className="relative z-10 max-w-3xl mx-auto px-6 text-center">
              <span className="text-[#ae895e] text-[10px] md:text-xs uppercase tracking-[0.3em] font-bold mb-3 md:mb-4 block">03</span>
              <h3 className="text-3xl md:text-5xl font-light text-white/95 mb-6 md:mb-8 tracking-wide">
                {t('atmosphere.sec3Title')}
              </h3>
              <p className="text-white/70 leading-relaxed md:leading-loose font-light text-base md:text-xl">
                {t('atmosphere.sec3Desc')}
              </p>
              <button
                onClick={() => handleNavClick('menu')}
                className="mt-8 md:mt-12 px-8 md:px-10 py-4 border border-[#ae895e]/50 text-[#ae895e] hover:bg-[#ae895e] hover:text-black transition-all duration-500 uppercase tracking-[0.2em] text-[10px] md:text-xs font-bold cursor-pointer"
              >
                {t('header.exploreMenu')}
              </button>
            </div>
          </AnimatedSection>

        </div>

        {/* Full Width Gallery Teaser at bottom */}
        <div className="max-w-full mx-auto mt-20 md:mt-32 px-4 md:px-8">
          <div className="text-center mb-10 md:mb-12">
            <h4 className="text-[#ae895e] uppercase tracking-[0.4em] text-[10px] md:text-xs font-medium animate-fade-up-init">{t('atmosphere.gallery')}</h4>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 md:gap-6">
            <div className="aspect-square overflow-hidden border border-white/5 opacity-70 hover:opacity-100 transition-opacity duration-500">
              <ImageWithSkeleton src={bararea} alt="Detail 1" />
            </div>
            <div className="aspect-square overflow-hidden border border-white/5 opacity-70 hover:opacity-100 transition-opacity duration-500 md:translate-y-8">
              <ImageWithSkeleton src={atmosphere2} alt="Detail 2" />
            </div>
            <div className="aspect-square overflow-hidden border border-white/5 opacity-70 hover:opacity-100 transition-opacity duration-500">
              <ImageWithSkeleton src={specialevent} alt="Detail 3" />
            </div>
            <div className="aspect-square overflow-hidden border border-white/5 opacity-70 hover:opacity-100 transition-opacity duration-500 md:translate-y-8">
              <ImageWithSkeleton src={culinarydetail} alt="Detail 4" />
            </div>
          </div>
        </div>

      </div>
      <Footer />
    </>
  );
};

export default Atmosphere;
