import { useEffect, useRef } from 'react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { useLanguage } from '../contexts/LanguageContext';
import athmosphere from '../assets/restaurant/atmosphere.jpg';
import specialevent from '../assets/restaurant/specialevent.jpg';
import culinarydetail from '../assets/restaurant/culinarydetail.jpg';
import plating from '../assets/restaurant/signaturedish.jpg';
import freshingredients from '../assets/restaurant/freshingredients.jpg';
import bararea from '../assets/restaurant/bararea.jpg';
// import plating from '../assets/restaurant/plating.jpg';
import signature from '../assets/restaurant/signature.jpg'

gsap.registerPlugin(ScrollTrigger);

const ImageGrid = () => {
  const gridRef = useRef<HTMLDivElement>(null);
  const { language } = useLanguage();
  const dataLang: 'en' | 'ka' = language === 'ka' ? 'ka' : 'en';

  const images = [
    {
      src: athmosphere,
      className: 'col-span-1 row-span-1 md:col-span-2 md:row-span-2',
      translations: {
        en: {
          alt: 'Restaurant Atmosphere',
          comment: 'A cozy evening with warm lighting.'
        },
        ka: {
          alt: 'რესტორნის ატმოსფერო',
          comment: 'მყუდრო საღამო თბილი განათებით.'
        }
      }
    },
    {
      src: culinarydetail,
      className: 'col-span-1 row-span-1',
      translations: {
        en: {
          alt: 'Culinary Detail',
          comment: 'Precision in every plate.'
        },
        ka: {
          alt: 'კულინარიული დეტალები',
          comment: 'სიზუსტე თითოეულ თეფშზე.'
        }
      }
    },
    {
      src: '/black-logo.png',
      className: 'col-span-1 row-span-1',
      translations: {
        en: {
          alt: 'Interior Design',
          comment: 'Modern aesthetics meet comfort.'
        },
        ka: {
          alt: 'ინტერიერის დიზაინი',
          comment: 'თანამედროვე ესთეტიკა და კომფორტი.'
        }
      }
    },
    {
      src: specialevent,
      className: 'col-span-1 row-span-1 md:row-span-2',
      translations: {
        en: {
          alt: 'Special Event',
          comment: 'Celebrating moments that matter.'
        },
        ka: {
          alt: 'განსაკუთრებული ღონისძიება',
          comment: 'მნიშვნელოვანი მომენტების აღნიშვნა.'
        }
      }
    },
    {
      src: signature,
      className: 'col-span-1 row-span-1',
      translations: {
        en: {
          alt: 'Signature Dish',
          comment: 'Our chef’s masterpiece. "Madambovari"'
        },
        ka: {
          alt: 'საფირმო კერძი',
          comment: 'ჩვენი შეფის შედევრი. "მადამბოვარი"'
        }
      }
    },
    {
      src: bararea,
      className: 'col-span-1 row-span-1 md:col-span-2',
      translations: {
        en: {
          alt: 'Bar Area',
          comment: 'Crafted cocktails and good vibes.'
        },
        ka: {
          alt: 'ბარის ზონა',
          comment: 'ავტორული კოქტეილები და კარგი განწყობა.'
        }
      }
    },
    {
      src: '/black-logo.png',
      className: 'col-span-1 row-span-1',
      translations: {
        en: {
          alt: 'Outdoor Seating',
          comment: 'Al fresco dining at its best.'
        },
        ka: {
          alt: 'გარე სივრცე',
          comment: 'საუკეთესო ვახშამი ღია ცის ქვეშ.'
        }
      }
    },
    {
      src: '/vite.svg',
      className: 'col-span-1 row-span-1 md:col-span-2 md:row-span-2',
      translations: {
        en: {
          alt: 'Chef at Work',
          comment: 'Passion behind the scenes.'
        },
        ka: {
          alt: 'შეფი მუშაობის პროცესში',
          comment: 'ვნება კულისებში.'
        }
      }
    },
    {
      src: freshingredients,
      className: 'col-span-1 row-span-1',
      translations: {
        en: {
          alt: 'Fresh Ingredients',
          comment: 'Farm to table goodness.'
        },
        ka: {
          alt: 'ახალი ინგრედიენტები',
          comment: 'ფერმიდან პირდაპირ მაგიდაზე.'
        }
      }
    },
    {
      src: plating,
      className: 'col-span-1 row-span-1',
      translations: {
        en: {
          alt: 'Plating',
          comment: 'Art on a plate.'
        },
        ka: {
          alt: 'სერვირება',
          comment: 'ხელოვნება თეფშზე.'
        }
      }
    },
    {
      src: '/black-logo.png',
      className: 'col-span-2 row-span-1',
      translations: {
        en: {
          alt: 'Wine Selection',
          comment: 'The perfect pairing.'
        },
        ka: {
          alt: 'ღვინის არჩევანი',
          comment: 'იდეალური შეხამება.'
        }
      }
    },
  ];

  useEffect(() => {
    const ctx = gsap.context(() => {
      const items = gsap.utils.toArray<HTMLElement>('.grid-item');
      const isDesktop = window.innerWidth >= 768;

      items.forEach((item, index) => {
        // Alternating entrance animation
        const fromLeft = index % 2 === 0;

        gsap.fromTo(
          item,
          {
            opacity: 0,
            x: fromLeft ? -100 : 100,
            y: 50
          },
          {
            opacity: 1,
            x: 0,
            y: 0,
            duration: 1,
            ease: 'power3.out',
            scrollTrigger: {
              trigger: item,
              start: 'top 85%',
              end: 'top 50%',
              toggleActions: 'play none none reverse',
            }
          }
        );

        const textOverlay = item.querySelector('.text-overlay');
        if (textOverlay && isDesktop) {
          // Only hide text initially on desktop
          gsap.set(textOverlay.children, { y: 20, opacity: 0 });
        }
      });
    }, gridRef);

    return () => ctx.revert();
  }, []);

  const handleMouseEnter = (e: React.MouseEvent<HTMLDivElement>) => {
    if (window.innerWidth < 768) return; // Disable hover on mobile

    const target = e.currentTarget;
    const textItems = target.querySelectorAll('.text-overlay > *');
    gsap.to(textItems, {
      y: 0,
      opacity: 1,
      duration: 0.4,
      stagger: 0.1,
      ease: 'power2.out'
    });

    const img = target.querySelector('img');
    gsap.to(img, {
      scale: 1.1,
      duration: 0.7,
      ease: 'power2.out'
    });
  };

  const handleMouseLeave = (e: React.MouseEvent<HTMLDivElement>) => {
    if (window.innerWidth < 768) return; // Disable hover on mobile

    const target = e.currentTarget;
    const textItems = target.querySelectorAll('.text-overlay > *');
    gsap.to(textItems, {
      y: 20,
      opacity: 0,
      duration: 0.3,
      stagger: 0.05,
      ease: 'power2.in'
    });

    const img = target.querySelector('img');
    gsap.to(img, {
      scale: 1,
      duration: 0.7,
      ease: 'power2.out'
    });
  };

  return (
    <>
      <div className="w-full py-12 bg-[#222]" ref={gridRef}>
        <div className="w-full px-4">
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 auto-rows-[350px] md:auto-rows-[300px] grid-flow-dense">
            {images.map((img, index) => (
              <div
                key={index}
                onMouseEnter={handleMouseEnter}
                onMouseLeave={handleMouseLeave}
                className={`grid-item relative group overflow-hidden rounded-xl bg-[#1a1a1a] ${img.className} shadow-lg`}
              >
                <div className="absolute inset-0 bg-black/40 md:bg-black/20 md:group-hover:bg-black/40 transition-colors duration-500 z-10" />

                <img
                  src={img.src}
                  alt={img.translations[dataLang].alt}
                  className="w-full h-full object-cover"
                />

                <div className="text-overlay absolute inset-0 flex flex-col justify-end p-6 z-20 opacity-100 md:opacity-0 md:group-hover:opacity-100 transition-opacity duration-300">
                  <h3 className={`text-white font-bold mb-2 md:transform md:translate-y-4 font-rossten tracking-wider uppercase ${language === 'ka' ? 'text-xl md:text-2xl' : 'text-2xl md:text-4xl'}`}>{img.translations[dataLang].alt}</h3>
                  <p className={`text-[#a89763] font-medium tracking-wide md:transform md:translate-y-4 font-rossten uppercase ${language === 'ka' ? 'text-xs md:text-lg' : 'text-sm md:text-xl'}`}>{img.translations[dataLang].comment}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );
};

export default ImageGrid;
