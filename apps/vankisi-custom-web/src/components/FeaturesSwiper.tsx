import { useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Swiper, SwiperSlide } from 'swiper/react';
import { Autoplay, Pagination } from 'swiper/modules';
import type { Swiper as SwiperType } from 'swiper';
import { useLanguage } from '../contexts/LanguageContext';

const FeaturesSwiper = () => {
  const { language } = useLanguage();
  const dataLang: 'en' | 'ka' = language === 'ka' ? 'ka' : 'en';
  const swiperRef = useRef<SwiperType | null>(null);
  const [isPaused, setIsPaused] = useState(false);
  const [_, setActiveIndex] = useState(0);

  // Sample feature images/content - you can replace these with your actual content
  const features = [
    {
      image: '/logo.png',
      translations: {
        en: {
          title: 'Traditional Recipes',
          description: 'Authentic Georgian cuisine passed down through generations'
        },
        ka: {
          title: 'ტრადიციული რეცეპტები',
          description: 'თაობიდან თაობას გადაცემული ავთენტური ქართული სამზარეულო'
        }
      }
    },
    {
      image: '/vite.svg',
      translations: {
        en: {
          title: 'Fresh Ingredients',
          description: 'Locally sourced, organic ingredients for the best taste'
        },
        ka: {
          title: 'ახალი ინგრედიენტები',
          description: 'ადგილობრივი, ორგანული პროდუქტები საუკეთესო გემოსთვის'
        }
      }
    },
    {
      image: '/logo.png',
      translations: {
        en: {
          title: 'Cozy Atmosphere',
          description: 'Experience the warmth of Georgian hospitality'
        },
        ka: {
          title: 'მყუდრო გარემო',
          description: 'გამოცადეთ ქართული სტუმართმოყვარეობის სითბო'
        }
      }
    },
  ];

  const togglePause = () => {
    if (swiperRef.current) {
      if (isPaused) {
        swiperRef.current.autoplay.start();
      } else {
        swiperRef.current.autoplay.stop();
      }
      setIsPaused(!isPaused);
    }
  };

  return (
    <div className="w-full max-w-4xl px-4 relative pb-8">
      <Swiper
        modules={[Autoplay, Pagination]}
        spaceBetween={20}
        slidesPerView={1}
        centeredSlides={false}
        breakpoints={{
          640: {
            slidesPerView: 1.3,
            spaceBetween: 20,
          },
          768: {
            slidesPerView: 1.4,
            spaceBetween: 25,
          },
          1024: {
            slidesPerView: 1.5,
            spaceBetween: 30,
          },
        }}
        autoplay={{
          delay: 5000,
          disableOnInteraction: false,
          pauseOnMouseEnter: false,
        }}
        pagination={{
          clickable: true,
        }}
        loop={true}
        onSwiper={(swiper) => {
          swiperRef.current = swiper;
        }}
        onSlideChange={(swiper) => {
          setActiveIndex(swiper.realIndex);

          if (!isPaused) {
            swiper.autoplay.start();
          }
        }}
        className="features-swiper h-48 sm:h-56 md:h-64"
      >
        {features.map((feature, index) => (
          <SwiperSlide key={index}>
            {({ isActive, isNext }) => (
              <Link to={`/${language}/events`} className={`block h-full bg-gradient-to-br from-[#222] to-[#333] rounded-lg overflow-hidden shadow-lg transition-all duration-500 group ${isActive ? 'opacity-100 scale-100' : isNext ? 'opacity-60 blur-sm scale-95' : 'opacity-40 blur-md scale-90'
                }`}>
                <div className="h-full flex flex-col items-center justify-center pt-8 px-4 pb-6 text-center relative">
                  <img
                    src={feature.image}
                    alt={feature.translations[dataLang].title}
                    className="w-16 h-16 sm:w-20 sm:h-20 md:w-24 md:h-24 object-contain mb-4 opacity-80 group-hover:scale-110 transition-transform duration-300"
                  />
                  <h4 className={`text-[#a89763] font-semibold pt-6 mb-1 font-rossten uppercase tracking-wider ${language === 'ka'
                    ? 'text-xs sm:text-sm md:text-base' // Smaller for Georgian
                    : 'text-sm sm:text-base md:text-lg' // Default size
                    }`}>
                    {feature.translations[dataLang].title}
                  </h4>

                  <div className="mt-auto opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-opacity duration-300">
                    <span className="text-[#a89763] text-sm border-b border-[#a89763] pb-0.5">
                      {language === 'ka' ? 'გაიგე მეტი' : 'Explore'}
                    </span>
                  </div>
                </div>
              </Link>
            )}
          </SwiperSlide>
        ))}
      </Swiper>

      {/* Swipe Hint */}
      <div className="flex items-center justify-center gap-2 mt-3 opacity-60">
        <svg className="w-4 h-4 text-[#a89763] animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16l-4-4m0 0l4-4m-4 4h18" />
        </svg>
        <span className={`${language === 'ka' ? 'text-sm' : 'text-xl'} text-gray-400`}>{language === 'ka' ? 'გაუსვით სანახავად' : 'Swipe to explore'}</span>
        <svg className="w-4 h-4 text-[#a89763] animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
        </svg>
      </div>

      {/* Pause/Play Button */}
      <button
        onClick={togglePause}
        className="absolute cursor-pointer top-2 right-2 z-20 bg-[#a89763]/80 hover:bg-[#a89763] text-black p-2 rounded-full transition-all duration-300 hover:scale-110 backdrop-blur-sm shadow-lg hidden md:block"
        aria-label={isPaused ? "Play slideshow" : "Pause slideshow"}
      >
        {isPaused ? (
          <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
            <path d="M8 5v14l11-7z" />
          </svg>
        ) : (
          <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
          </svg>
        )}
      </button>
    </div>
  );
};

export default FeaturesSwiper;
