import { useState, useRef, useEffect, useCallback } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';
import { menuService } from '../services/api';
import { useStickyOffsets } from '../hooks/useStickyOffsets';
import type { MenuCategory, MenuItem, MenuSection, PreOrderItem } from '../types/menu';
import {
  normalizeCategory,
  hasFullCategoryDetail,
  getCategoryName,
  getItemName,
  getSectionName,
  getFirstItemImage,
} from '../utils/menuNormalize';

const RES_KEY = 'vankisi_reservation';
const PREORDER_KEY = 'vankisi_preorder';
const loadRes = () => { try { return JSON.parse(localStorage.getItem(RES_KEY) || '{}'); } catch { return {}; } };
const loadPreOrder = (): PreOrderItem[] => { try { return JSON.parse(localStorage.getItem(PREORDER_KEY) || '[]'); } catch { return []; } };
const savePreOrder = (items: PreOrderItem[]) => localStorage.setItem(PREORDER_KEY, JSON.stringify(items));

const FALLBACK_IMAGES = [
  'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&q=80&w=1200',
  'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&q=80&w=1200',
  'https://images.unsplash.com/photo-1514516874246-818274d82eb1?auto=format&fit=crop&q=80&w=1200',
];

const AnimatedSection = ({ children, className = '', delay = 0 }: { children: React.ReactNode; className?: string; delay?: number }) => {
  const [isVisible, setIsVisible] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const obs = new IntersectionObserver(
      e => e.forEach(en => { if (en.isIntersecting) { setIsVisible(true); obs.unobserve(en.target); } }),
      { threshold: 0.1 },
    );
    if (ref.current) obs.observe(ref.current);
    return () => obs.disconnect();
  }, []);
  return (
    <div
      ref={ref}
      className={`transition-all duration-1000 ease-out ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'} ${className}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </div>
  );
};

// ─── Menu item row ────────────────────────────────────────────────────────────
interface MenuItemRowProps {
  item: MenuItem;
  itemName: string;
  quantity: number;
  isPreOrderMode: boolean;
  addLabel: string;
  onUpdate: (payload: { id: string; name: string; price: number }, delta: number) => void;
  delay: number;
}

const MenuItemRow = ({ item, itemName, quantity, isPreOrderMode, addLabel, onUpdate, delay }: MenuItemRowProps) => {
  const hasVariants = item.hasVariants && item.variants && item.variants.length > 0;
  const basePrice = hasVariants ? Math.min(...item.variants!.map(v => v.price)) : item.price;

  if (hasVariants) {
    return (
      <AnimatedSection delay={delay} className="group space-y-3">
        <h4 className={`text-lg sm:text-xl font-light tracking-wide transition-colors ${
          quantity > 0 ? 'text-[#ae895e]' : 'text-white/90 group-hover:text-[#ae895e]'
        }`}>
          {itemName}
        </h4>
        <div className="flex flex-wrap gap-2">
          {item.variants!.map(variant => {
            const label = `${variant.size}L — ${variant.price}₾`;
            return (
              <button
                key={variant.id}
                onClick={() => isPreOrderMode && onUpdate({ id: variant.id, name: `${itemName} ${variant.size}L`, price: variant.price }, 1)}
                disabled={!isPreOrderMode}
                className={`text-xs border rounded-full px-3 py-1.5 transition-all ${
                  isPreOrderMode
                    ? 'border-white/20 text-white/60 hover:border-[#ae895e] hover:text-[#ae895e]'
                    : 'border-white/10 text-white/30 cursor-default'
                }`}
              >
                {label}
              </button>
            );
          })}
        </div>
      </AnimatedSection>
    );
  }

  return (
    <AnimatedSection delay={delay} className="group">
      <div className="flex flex-col sm:flex-row sm:justify-between sm:items-end gap-2 mb-3">
        <h4 className={`text-lg sm:text-xl font-light tracking-wide transition-colors sm:bg-[#050505] sm:pr-4 relative z-10 min-w-0 ${
          quantity > 0 ? 'text-[#ae895e]' : 'text-white/90 group-hover:text-[#ae895e]'
        }`}>
          {itemName}
        </h4>

        <div className="hidden sm:block flex-grow border-b border-dotted border-white/20 mb-2 mx-4 relative z-0" />

        <div className="sm:bg-[#050505] sm:pl-4 relative z-10 flex items-center gap-4 sm:gap-6 shrink-0">
          <span className={`text-lg sm:text-xl font-light ${quantity > 0 ? 'text-[#ae895e]' : 'text-white/80'}`}>
            {basePrice}₾
          </span>

          {isPreOrderMode && (
            <div className="flex items-center gap-3">
              {quantity > 0 ? (
                <div className="flex items-center gap-3 bg-[#ae895e]/10 border border-[#ae895e]/50 rounded-full px-3 py-1">
                  <button onClick={() => onUpdate({ id: item.id, name: itemName, price: item.price }, -1)} className="text-[#ae895e] hover:text-white p-1 transition-colors">
                    <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M20 12H4" />
                    </svg>
                  </button>
                  <span className="text-[#ae895e] text-sm w-4 text-center font-medium">{quantity}</span>
                  <button onClick={() => onUpdate({ id: item.id, name: itemName, price: item.price }, 1)} className="text-[#ae895e] hover:text-white p-1 transition-colors">
                    <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
                    </svg>
                  </button>
                </div>
              ) : (
                <button
                  onClick={() => onUpdate({ id: item.id, name: itemName, price: item.price }, 1)}
                  className="flex items-center gap-2 border border-white/20 text-white/50 hover:border-[#ae895e] hover:text-[#ae895e] rounded-full px-4 py-1.5 text-xs tracking-wider transition-all"
                >
                  <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
                  </svg>
                  {addLabel}
                </button>
              )}
            </div>
          )}
        </div>
      </div>
    </AnimatedSection>
  );
};

// ─── Category block ───────────────────────────────────────────────────────────
interface CategoryBlockProps {
  category: MenuCategory;
  idx: number;
  dataLang: 'en' | 'ka';
  scrollMarginTop: number;
  isPreOrderMode: boolean;
  preOrderItems: PreOrderItem[];
  addLabel: string;
  onUpdateQuantity: (payload: { id: string; name: string; price: number }, delta: number) => void;
}

const shouldShowSectionHeader = (section: MenuSection, category: MenuCategory, dataLang: 'en' | 'ka') => {
  const sectionName = getSectionName(section, dataLang);
  if (!sectionName) return false;
  if (category.displayMode === 'grouped' && category.sections.length > 1) return true;
  if (category.sections.length > 1) return true;
  return sectionName !== getCategoryName(category, dataLang);
};

const CategoryBlock = ({
  category, idx, dataLang, scrollMarginTop,
  isPreOrderMode, preOrderItems, addLabel, onUpdateQuantity,
}: CategoryBlockProps) => {
  const featuredImage = getFirstItemImage(category) || FALLBACK_IMAGES[idx % 3];
  let itemDelay = 0;

  return (
    <div id={`category-${category.slug}`} className="mb-24 sm:mb-32 pt-6 sm:pt-8" style={{ scrollMarginTop }}>
      <AnimatedSection className="flex flex-col sm:flex-row items-center gap-3 sm:gap-6 mb-8">
        <div className="hidden sm:block h-[1px] bg-white/10 flex-grow w-full" />
        <h2 className="text-xl sm:text-3xl font-light tracking-wide text-[#ae895e] text-center px-2 max-w-full">
          {getCategoryName(category, dataLang)}
        </h2>
        <div className="hidden sm:block h-[1px] bg-white/10 flex-grow w-full" />
      </AnimatedSection>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-16 items-start">
        <AnimatedSection
          delay={100}
          className={`relative aspect-[4/5] overflow-hidden bg-[#0a0a0a] ${idx % 2 !== 0 ? 'lg:order-2' : ''}`}
        >
          <img
            src={featuredImage}
            alt={getCategoryName(category, dataLang)}
            className="w-full h-full object-cover opacity-70 hover:opacity-100 transition-opacity duration-700 hover:scale-105 transform"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-[#050505] via-transparent to-transparent opacity-90" />
        </AnimatedSection>

        <div className={`space-y-10 sm:space-y-14 ${idx % 2 !== 0 ? 'lg:order-1' : ''}`}>
          {category.sections.map(section => (
            <div key={section.slug} className="space-y-6 sm:space-y-8">
              {shouldShowSectionHeader(section, category, dataLang) && (
                <h3 className="text-sm sm:text-base font-light tracking-wide text-[#ae895e] border-b border-[#ae895e]/20 pb-3">
                  {getSectionName(section, dataLang)}
                </h3>
              )}
              {section.items.map(item => {
                const cartItem = preOrderItems.find(i => i.id === item.id);
                const quantity = cartItem?.quantity ?? 0;
                const delay = 200 + itemDelay * 80;
                itemDelay += 1;
                return (
                  <MenuItemRow
                    key={item.id}
                    item={item}
                    itemName={getItemName(item, dataLang)}
                    quantity={quantity}
                    isPreOrderMode={isPreOrderMode}
                    addLabel={addLabel}
                    onUpdate={onUpdateQuantity}
                    delay={delay}
                  />
                );
              })}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ─── Main component ───────────────────────────────────────────────────────────
const Menu = () => {
  const { language } = useLanguage();
  const dataLang: 'en' | 'ka' = language === 'ka' ? 'ka' : 'en';
  const navigate = useNavigate();
  const params = useParams<{ lang: string }>();
  const currentLang = params.lang || language;

  const [categories, setCategories] = useState<MenuCategory[]>([]);
  const [activeCategory, setActiveCategory] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [isPreOrderMode, setIsPreOrderMode] = useState(false);
  const [preOrderItems, setPreOrderItems] = useState<PreOrderItem[]>([]);
  const [isCartOpen, setIsCartOpen] = useState(false);
  const [isWideLayout, setIsWideLayout] = useState(false);

  const categoryNavRef = useRef<HTMLDivElement>(null);
  const mobileNavRef = useRef<HTMLDivElement>(null);
  const isClickScrollingRef = useRef(false);
  const clickScrollTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const syncNavScrollRef = useRef(false);

  const { navHeight, scrollOffset } = useStickyOffsets(
    categoryNavRef,
    categories.length > 0 && !isWideLayout,
  );

  useEffect(() => {
    const mq = window.matchMedia('(min-width: 1280px)');
    const update = () => setIsWideLayout(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);

  useEffect(() => () => clearTimeout(clickScrollTimerRef.current), []);

  const loadMenu = useCallback(async () => {
    const list = await menuService.getAllCategories();
    const summaries = (Array.isArray(list) ? list : []).map(normalizeCategory);

    const detailed = await Promise.all(
      summaries.map(async summary => {
        if (hasFullCategoryDetail(summary) && summary.sections.some(s => s.items.length > 0)) {
          return summary;
        }
        const detail = await menuService.getCategoryBySlug(summary.slug);
        return normalizeCategory(detail);
      }),
    );

    return { detailed };
  }, []);

  useEffect(() => {
    (async () => {
      try {
        setLoading(true);
        const { detailed } = await loadMenu();
        setCategories(detailed);
        if (detailed.length > 0) setActiveCategory(detailed[0].slug);
      } catch {
        setError('Failed to load menu data');
      } finally {
        setLoading(false);
      }
    })();
  }, [loadMenu]);

  useEffect(() => {
    const res = loadRes();
    if (res.resStep === 3) {
      setIsPreOrderMode(true);
      setPreOrderItems(loadPreOrder());
    }
  }, []);

  // Scroll spy — update active category while scrolling
  useEffect(() => {
    if (!categories.length) return;

    let ticking = false;

    const updateActiveFromScroll = () => {
      if (isClickScrollingRef.current) return;
      if (ticking) return;
      ticking = true;

      requestAnimationFrame(() => {
        ticking = false;

        const anchor = scrollOffset + 24;
        let current = categories[0].slug;

        for (const cat of categories) {
          const el = document.getElementById(`category-${cat.slug}`);
          if (el && el.getBoundingClientRect().top <= anchor) {
            current = cat.slug;
          }
        }

        setActiveCategory(prev => {
          if (prev === current) return prev;
          syncNavScrollRef.current = true;
          return current;
        });
      });
    };

    updateActiveFromScroll();
    window.addEventListener('scroll', updateActiveFromScroll, { passive: true });
    window.addEventListener('resize', updateActiveFromScroll);

    return () => {
      window.removeEventListener('scroll', updateActiveFromScroll);
      window.removeEventListener('resize', updateActiveFromScroll);
    };
  }, [categories, scrollOffset]);

  const syncCategoryNav = (slug: string, smooth: boolean) => {
    const container = mobileNavRef.current;
    const btn = container?.querySelector(`[data-slug="${slug}"]`) as HTMLElement | null;
    if (!container || !btn) return;

    if (smooth) {
      btn.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
      return;
    }

    const target = btn.offsetLeft - (container.clientWidth - btn.offsetWidth) / 2;
    container.scrollTo({ left: Math.max(0, target), behavior: 'instant' });
  };

  // Keep horizontal category nav aligned with active item (instant while scrolling)
  useEffect(() => {
    if (!syncNavScrollRef.current || !activeCategory) return;
    syncNavScrollRef.current = false;
    syncCategoryNav(activeCategory, false);
  }, [activeCategory]);

  const updateQuantity = (item: { id: string; name: string; price: number }, delta: number) => {
    setPreOrderItems(prev => {
      const existing = prev.find(i => i.id === item.id);
      let next: PreOrderItem[];
      if (existing) {
        const newQty = existing.quantity + delta;
        if (newQty <= 0) next = prev.filter(i => i.id !== item.id);
        else next = prev.map(i => i.id === item.id ? { ...i, quantity: newQty } : i);
      } else if (delta > 0) {
        next = [...prev, { id: item.id, name: item.name, price: item.price, quantity: 1 }];
      } else {
        return prev;
      }
      savePreOrder(next);
      return next;
    });
  };

  const preOrderTotal = preOrderItems.reduce((s, i) => s + i.price * i.quantity, 0);
  const preOrderCount = preOrderItems.reduce((s, i) => s + i.quantity, 0);
  const addLabel = language === 'ka' ? 'დამატება' : 'Add';

  const scrollToCategory = (slug: string) => {
    setActiveCategory(slug);
    isClickScrollingRef.current = true;
    clearTimeout(clickScrollTimerRef.current);

    const el = document.getElementById(`category-${slug}`);
    if (el) {
      const y = el.getBoundingClientRect().top + window.pageYOffset - scrollOffset;
      window.scrollTo({ top: y, behavior: 'smooth' });
    }
    syncCategoryNav(slug, true);

    clickScrollTimerRef.current = setTimeout(() => {
      isClickScrollingRef.current = false;
    }, 600);
  };

  const categoryBtnClass = (slug: string, variant: 'horizontal' | 'vertical') => {
    const active = activeCategory === slug;
    if (variant === 'horizontal') {
      return `whitespace-nowrap uppercase tracking-[0.08em] sm:tracking-[0.1em] text-sm sm:text-base transition-all duration-300 py-3 sm:py-3.5 pb-2.5 border-b-2 shrink-0 snap-start min-h-[48px] sm:min-h-[52px] flex items-center ${
        active ? 'text-[#ae895e] border-[#ae895e] font-semibold' : 'text-white/40 border-transparent hover:text-white'
      }`;
    }
    return `text-left py-2 xl:py-2.5 pr-2 text-[11px] xl:text-xs uppercase tracking-[0.1em] xl:tracking-[0.12em] leading-snug transition-all duration-300 border-l-2 -ml-[17px] pl-3 xl:pl-4 ${
      active ? 'text-[#ae895e] border-[#ae895e] font-semibold' : 'text-white/40 border-transparent hover:text-white'
    }`;
  };

  const categoryScrollMargin = isWideLayout ? navHeight + 16 : scrollOffset;

  const handleContinue = () => {
    const res = loadRes();
    localStorage.setItem(RES_KEY, JSON.stringify({ ...res, resStep: 4 }));
    navigate(`/${currentLang}`, { state: { preserveScroll: true } });
    setTimeout(() => {
      document.getElementById('reservation-section')?.scrollIntoView({ behavior: 'smooth' });
    }, 500);
  };

  if (loading) {
    return (
      <section id="menu-page" className="min-h-screen bg-[#050505] flex items-center justify-center">
        <div className="text-center space-y-6">
          <div className="relative w-14 h-14 mx-auto">
            <div className="w-14 h-14 border-2 border-white/10 border-t-[#ae895e] rounded-full animate-spin" />
          </div>
          <p className="text-white/30 text-xs tracking-widest uppercase">
            {language === 'ka' ? 'მენიუ იტვირთება...' : 'Loading menu...'}
          </p>
        </div>
      </section>
    );
  }

  if (error) {
    return (
      <section id="menu-page" className="min-h-screen bg-[#050505] flex items-center justify-center">
        <div className="text-center space-y-6">
          <p className="text-red-400/70 font-light">{language === 'ka' ? 'შეცდომა მოხდა' : 'Failed to load menu'}</p>
          <button onClick={() => window.location.reload()} className="px-8 py-3 border border-[#ae895e]/40 text-[#ae895e] hover:bg-[#ae895e] hover:text-black transition-all duration-300 text-xs uppercase tracking-widest">
            {language === 'ka' ? 'ხელახლა' : 'Try Again'}
          </button>
        </div>
      </section>
    );
  }

  return (
    <section id="menu-page" className="min-h-screen bg-[#050505] pt-24 sm:pt-28 lg:pt-32 pb-24 sm:pb-32 relative text-white overflow-x-clip">

      <div className="max-w-7xl mx-auto px-5 sm:px-6 lg:px-8 mb-16 text-center">
        {isPreOrderMode ? (
          <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-bold block mb-6 animate-pulse">
            {language === 'ka' ? 'რეზერვაციის მენიუ' : 'Reservation Menu'}
          </span>
        ) : (
          <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-medium block mb-6">A La Carte</span>
        )}
        <h1 className="text-5xl md:text-7xl font-light mb-8 tracking-wide text-white/95">
          {language === 'ka' ? (
            <>ჩვენი <span className="italic font-serif text-[#ae895e]">მენიუ</span></>
          ) : (
            <>Our <span className="italic font-serif text-[#ae895e]">Menu</span></>
          )}
        </h1>
        <p className="text-white/40 max-w-2xl mx-auto leading-loose font-light text-lg">
          {language === 'ka'
            ? 'ჩვენი შეფ-მზარეულის მიერ ოსტატურად შექმნილი კულინარიული შედევრები, სადაც თითოეული ინგრედიენტი ყვება საკუთარ, უნიკალურ ისტორიას.'
            : "Culinary masterpieces by our chef, where every ingredient tells its own unique story."}
        </p>
      </div>

      {/* Horizontal category nav — mobile & tablet (< xl) */}
      <div
        ref={categoryNavRef}
        className="xl:hidden sticky z-40 bg-[#050505]/95 backdrop-blur-md border-y border-white/5 mb-6 sm:mb-8"
        style={{ top: navHeight }}
      >
        <div className="max-w-7xl mx-auto px-5 sm:px-6 md:px-8">
          <div className="relative">
            <div className="pointer-events-none absolute inset-y-0 right-0 w-6 sm:w-8 bg-gradient-to-l from-[#050505] to-transparent z-10" />
            <div
              ref={mobileNavRef}
              className="flex w-full overflow-x-auto hide-scrollbar py-3 sm:py-4 gap-4 sm:gap-5 md:gap-6 snap-x snap-mandatory overscroll-x-contain [-webkit-overflow-scrolling:touch]"
            >
              {categories.map(cat => (
                <button
                  key={cat.slug}
                  data-slug={cat.slug}
                  onClick={() => scrollToCategory(cat.slug)}
                  className={categoryBtnClass(cat.slug, 'horizontal')}
                >
                  {getCategoryName(cat, dataLang)}
                </button>
              ))}
              <span className="shrink-0 w-5 sm:w-6" aria-hidden />
            </div>
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-5 sm:px-6 lg:px-8">
        <div className="flex gap-8 xl:gap-16 items-start">
          <aside
            className="hidden xl:block w-44 2xl:w-52 shrink-0 sticky z-30 self-start max-h-[calc(100dvh-6rem)] overflow-y-auto custom-scrollbar"
            style={{ top: navHeight + 16 }}
          >
            <nav className="flex flex-col gap-1 border-l border-white/10 pl-4">
              {categories.map(cat => (
                <button
                  key={cat.slug}
                  onClick={() => scrollToCategory(cat.slug)}
                  className={categoryBtnClass(cat.slug, 'vertical')}
                >
                  {getCategoryName(cat, dataLang)}
                </button>
              ))}
            </nav>
          </aside>

          <div className="flex-grow min-w-0">
            {categories.map((category, idx) => (
              <CategoryBlock
                key={category.slug}
                category={category}
                idx={idx}
                dataLang={dataLang}
                scrollMarginTop={categoryScrollMargin}
                isPreOrderMode={isPreOrderMode}
                preOrderItems={preOrderItems}
                addLabel={addLabel}
                onUpdateQuantity={updateQuantity}
              />
            ))}
          </div>
        </div>
      </div>

      {isPreOrderMode && (
        <>
          <div className="fixed bottom-6 md:bottom-10 left-1/2 -translate-x-1/2 z-50 flex items-center bg-[#0a0a0a]/95 backdrop-blur-xl border border-[#ae895e]/40 rounded-full p-1.5 shadow-[0_20px_50px_rgba(0,0,0,0.8)] w-[92%] max-w-sm md:max-w-md justify-between">
            <button onClick={() => setIsCartOpen(true)} className="flex items-center gap-3 px-4 py-2 hover:bg-white/5 rounded-full transition-colors group">
              <div className="relative">
                <svg className="w-5 h-5 text-[#ae895e] group-hover:scale-110 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.8} d="M6 2L3 6v14a2 2 0 002 2h14a2 2 0 002-2V6l-3-4zM3 6h18M16 10a4 4 0 01-8 0" />
                </svg>
                {preOrderCount > 0 && (
                  <span className="absolute -top-2 -right-2 bg-[#ae895e] text-[#050505] text-[10px] w-4 h-4 flex items-center justify-center rounded-full font-bold">
                    {preOrderCount}
                  </span>
                )}
              </div>
              <div className="flex flex-col items-start text-left">
                <span className="text-[9px] uppercase tracking-[0.2em] text-white/50 leading-none mb-1">
                  {language === 'ka' ? 'კალათა' : 'Cart'}
                </span>
                <span className="text-xs font-bold text-[#ae895e] leading-none">{preOrderTotal}₾</span>
              </div>
            </button>
            <button
              onClick={handleContinue}
              className="bg-[#ae895e] text-[#050505] px-6 py-3 rounded-full uppercase tracking-[0.1em] md:tracking-[0.2em] text-[10px] md:text-xs font-bold hover:bg-white transition-colors flex items-center gap-2 whitespace-nowrap"
            >
              {language === 'ka' ? 'გაგრძელება' : 'Continue'}
              <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
              </svg>
            </button>
          </div>

          <div
            className={`fixed inset-0 bg-black/60 backdrop-blur-sm z-[60] transition-opacity duration-500 ${isCartOpen ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'}`}
            onClick={() => setIsCartOpen(false)}
          />

          <div className={`fixed top-0 right-0 h-full w-full max-w-md bg-[#0a0a0a] border-l border-white/10 z-[70] transform transition-transform duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] flex flex-col ${isCartOpen ? 'translate-x-0' : 'translate-x-full'}`}>
            <div className="p-6 border-b border-white/5 flex justify-between items-center">
              <div className="flex items-center gap-3 text-[#ae895e]">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.8} d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z" />
                </svg>
                <h3 className="text-sm font-medium tracking-[0.2em] uppercase">
                  {language === 'ka' ? 'თქვენი შეკვეთა' : 'Your Order'}
                </h3>
              </div>
              <button onClick={() => setIsCartOpen(false)} className="text-white/50 hover:text-white transition-colors">
                <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <div className="flex-grow overflow-y-auto custom-scrollbar p-6">
              {preOrderItems.length === 0 ? (
                <div className="h-full flex flex-col items-center justify-center text-center text-white/30 space-y-4">
                  <svg className="w-12 h-12 opacity-40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.2} d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z" />
                  </svg>
                  <p className="text-sm font-light tracking-wide whitespace-pre-line">
                    {language === 'ka' ? 'კალათა ცარიელია.\nდაამატეთ კერძები მენიუდან.' : 'Cart is empty.\nAdd items from the menu.'}
                  </p>
                </div>
              ) : (
                <div className="space-y-6">
                  {preOrderItems.map(item => (
                    <div key={item.id} className="flex gap-4 border-b border-white/5 pb-6">
                      <div className="flex-grow flex flex-col justify-between">
                        <h4 className="text-sm font-light text-white/90 mb-2">{item.name}</h4>
                        <div className="flex justify-between items-center">
                          <span className="text-[#ae895e] font-medium">{item.price * item.quantity}₾</span>
                          <div className="flex items-center gap-3 bg-white/5 border border-white/10 rounded-full px-3 py-1">
                            <button onClick={() => updateQuantity(item, -1)} className="text-white/50 hover:text-[#ae895e] transition-colors p-1">
                              {item.quantity === 1 ? (
                                <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                                  <path strokeLinecap="round" strokeLinejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                </svg>
                              ) : (
                                <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                                  <path strokeLinecap="round" strokeLinejoin="round" d="M20 12H4" />
                                </svg>
                              )}
                            </button>
                            <span className="text-white text-xs w-4 text-center">{item.quantity}</span>
                            <button onClick={() => updateQuantity(item, 1)} className="text-white/50 hover:text-[#ae895e] transition-colors p-1">
                              <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}>
                                <path strokeLinecap="round" strokeLinejoin="round" d="M12 4v16m8-8H4" />
                              </svg>
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="p-6 border-t border-white/5 bg-[#050505]">
              <div className="flex justify-between items-center mb-6">
                <span className="text-white/60 font-light">{language === 'ka' ? 'ჯამი:' : 'Total:'}</span>
                <span className="text-2xl font-light text-[#ae895e]">{preOrderTotal}₾</span>
              </div>
              <button
                onClick={() => { setIsCartOpen(false); handleContinue(); }}
                className="w-full py-4 uppercase tracking-[0.2em] text-xs font-bold transition-all flex items-center justify-center gap-3 bg-[#ae895e] text-black hover:bg-white"
              >
                {language === 'ka' ? 'გაგრძელება' : 'Continue'}
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
                </svg>
              </button>
            </div>
          </div>
        </>
      )}
    </section>
  );
};

export default Menu;
