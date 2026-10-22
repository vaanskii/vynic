import { useRef, useEffect, useLayoutEffect, useState } from 'react';
import { Link, useNavigate, useParams, useLocation } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';
import {
  loadRes,
  saveRes,
  homeWizardStep,
  isReservationHomePath,
  clearStaleTableStepOnHome,
} from '../utils/reservationStorage';
import { useTr } from '../hooks/useTr';
import { reservationTablesPath } from '../routes/reservation';
import atmosphereImg from '../assets/restaurant/atmosphere.jpg';
import photoshoot from '../assets/restaurant/photoshoot1.jpg';
import khinkali from '../assets/restaurant/khinkali.jpg';
import atmosphere1 from '../assets/restaurant/athmosphere1.jpg';
import atmosphere2 from '../assets/restaurant/athmosphere2.jpg';
import ImageWithSkeleton from './ImageWithSkeleton';

// ─── Scroll-triggered fade-up wrapper ────────────────────────────────────────
const AnimatedSection = ({
  children,
  className = '',
  delay = 0,
}: {
  children: React.ReactNode;
  className?: string;
  delay?: number;
}) => {
  const [isVisible, setIsVisible] = useState(false);
  const domRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const observer = new IntersectionObserver(
      entries => entries.forEach(e => { if (e.isIntersecting) { setIsVisible(true); observer.unobserve(e.target); } }),
      { threshold: 0.15 }
    );
    if (domRef.current) observer.observe(domRef.current);
    return () => observer.disconnect();
  }, []);
  return (
    <div
      ref={domRef}
      className={`transition-all duration-1000 ease-out ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'} ${className}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </div>
  );
};

// ─── Inline Logo SVG ─────────────────────────────────────────────────────────
const LogoSVG = ({ className }: { className?: string }) => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" className={className}>
    <path fill="#ae895e" d="M133 151L151 167Q167 177 187 184L226 195L231 195L236 197L241 197L246 199L264 202L268 204L272 204L302 214Q329 226 348 248L350 251L363 269L376 301L377 308L382 321L382 325L384 328L391 354L393 357L405 396L405 401L407 408L408 434L407 435L407 445L406 446L405 457L398 478L397 477L399 466L399 439L395 419L393 416L393 413L391 410L391 407L386 395L384 385L382 383L373 353L368 342L366 333L361 322L361 319L359 317L359 314Q347 286 327 268L324 266Q309 252 288 245L267 239L256 238L250 236L245 236L239 234L233 234L208 229L192 224L170 213L167 213Q168 210 165 211L147 196L135 174Q136 167 133 165L133 151Z" />
    <path fill="#ae895e" d="M149 228L151 229Q150 232 153 231L171 245L198 256L214 259L218 261L225 261L230 263L247 265L257 268L263 268L293 277L313 288L328 303Q341 317 347 339L336 328L314 314L296 307L265 300L257 300L245 297L228 295L201 288Q178 280 163 264Q150 250 149 228Z" />
    <path fill="#ae895e" d="M176 299L198 311L218 318L238 322L245 322L272 327L278 327L297 331L317 339L332 350L332 352Q335 351 334 354L345 368L356 390L361 403L361 406L384 463L384 466L402 510L402 513L409 528L412 539L416 546L416 549L425 570L425 573Q428 574 427 571L509 367L512 356L512 350L506 339L495 334L487 334L488 329L586 329L586 334L584 334Q567 337 558 349L548 366Q545 378 539 387L537 395L516 442L516 445L514 447L507 466L505 468L505 471L500 479L498 487Q489 501 484 520L482 522L471 551L457 581L432 642L430 644L428 644L417 644L415 643Q413 645 412 643L411 638L404 623L404 620L393 595L393 592L388 582L388 579L386 577L384 568L382 566L373 543L373 540L371 538L363 515L359 508L359 505L354 495L352 487L345 472L345 469L331 436L323 413L311 386L302 373Q299 374 300 372L295 368Q296 365 294 366L283 359L264 352L235 345L229 345L216 341L201 333L186 320L184 317L176 304L176 299Z" />
  </svg>
);

// ─── Pre-order item type ──────────────────────────────────────────────────────
interface PreOrderItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}

// ─── LocalStorage helpers ─────────────────────────────────────────────────────
const PREORDER_KEY = 'vankisi_preorder';
const loadPreOrder = (): PreOrderItem[] => {
  try { return JSON.parse(localStorage.getItem(PREORDER_KEY) || '[]'); } catch { return []; }
};

// ─── Main Header / Home page ──────────────────────────────────────────────────
const Header = () => {
  const { language, t } = useLanguage();
  const navigate = useNavigate();
  const location = useLocation();
  const params = useParams<{ lang: string }>();
  const currentLang = params.lang || language;

  const tr = useTr();

  // Reservation state (step 2 only exists on the table map route)
  const [resStep, setResStep] = useState<number>(() => homeWizardStep(loadRes().resStep || 1));
  const [resDate, setResDate] = useState(() => loadRes().resDate || '');
  const [resTime, setResTime] = useState(() => loadRes().resTime || '19:00');
  const [resGuests, setResGuests] = useState(() => loadRes().resGuests || '');
  const [customerName, setCustomerName] = useState(() => loadRes().customerName || '');
  const [customerPhone, setCustomerPhone] = useState(() => loadRes().customerPhone || '');
  const [specialRequest, setSpecialRequest] = useState(() => loadRes().specialRequest || '');
  const [selectedTables, setSelectedTables] = useState<Set<string>>(() => new Set(loadRes().selectedTables || []));
  const [preOrderItems] = useState<PreOrderItem[]>(() => loadPreOrder());

  const resSectionRef = useRef<HTMLDivElement>(null);

  // Clear stale step 2 before paint so we never flash "აირჩიეთ მაგიდა" on home
  useLayoutEffect(() => {
    clearStaleTableStepOnHome(location.pathname);
    if (isReservationHomePath(location.pathname)) {
      setResStep((step) => (step === 2 ? 1 : step));
    }
  }, [location.pathname]);

  // Sync wizard step when returning from map / menu
  useEffect(() => {
    const saved = loadRes();
    if (isReservationHomePath(location.pathname)) {
      setResStep(homeWizardStep(saved.resStep || 1));
      if (saved.resDate) setResDate(saved.resDate);
      if (saved.resTime) setResTime(saved.resTime);
      if (saved.resGuests) setResGuests(saved.resGuests);
      if (saved.selectedTables?.length) {
        setSelectedTables(new Set(saved.selectedTables));
      }
    }
  }, [location.pathname, location.hash]);

  // Scroll to reservation after returning from the table map
  useEffect(() => {
    if (location.hash === '#reservation-section') {
      resSectionRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [location.hash, resStep]);

  const goToTableMap = () => {
    if (!resDate) return;
    const existing = loadRes();
    saveRes({
      ...existing,
      resStep: 2,
      resDate,
      resTime: resTime || '19:00',
      resGuests: resGuests || '2',
      selectedDate: resDate,
      selectedTime: resTime || '19:00',
      selectedTables: Array.from(selectedTables),
    });
    navigate(reservationTablesPath(currentLang, { date: resDate }));
  };

  const handleReservationBack = () => {
    if (resStep === 3) {
      const existing = loadRes();
      const date = resDate || existing.resDate || existing.selectedDate;
      saveRes({ ...existing, resStep: 2 });
      if (date) {
        navigate(reservationTablesPath(currentLang, { date }));
      } else {
        setResStep(1);
      }
      return;
    }
    setResStep(resStep - 1);
  };

  // Persist reservation state whenever it changes (never store step 2 on home)
  useEffect(() => {
    const existing = loadRes();
    const now = Date.now();
    const onHome = isReservationHomePath(location.pathname);
    const stepToSave = onHome ? homeWizardStep(resStep) : resStep;

    saveRes({
      ...existing,
      resStep: stepToSave,
      resDate,
      resTime,
      resGuests,
      customerName,
      customerPhone,
      specialRequest,
      selectedTables: Array.from(selectedTables),
      selectedDate: resDate,
      selectedTime: resTime,
      // Maintain metadata
      createdAt: existing.createdAt || now,
      lastActivity: now,
      timestamp: now, // Legacy
    });
  }, [resStep, resDate, resTime, resGuests, customerName, customerPhone, specialRequest, selectedTables, location.pathname]);

  // Scroll to reservation section
  const scrollToReservation = () => {
    resSectionRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  const handleNavClick = (path: string) => {
    navigate(`/${currentLang}/${path}`);
  };

  const preOrderTotal = preOrderItems.reduce((s, i) => s + i.price * i.quantity, 0);
  const preOrderCount = preOrderItems.reduce((s, i) => s + i.quantity, 0);

  // Navigate to menu in pre-order mode
  const goToPreOrderMenu = () => {
    saveRes({ ...loadRes(), resStep: 3 });
    navigate(`/${currentLang}/menu`);
  };

  // Step labels — date first, then 3D table selection
  const stepTitles: Record<number, string> = {
    1: tr('Enter Details', 'მიუთითეთ დეტალები', 'Укажите детали'),
    3: tr('Pre-order Menu', 'გასტრონომიული შერჩევა', 'Предзаказ меню'),
    4: tr('Confirm Booking', 'დაასრულეთ ჯავშანი', 'Подтвердите бронь'),
  };

  const wizardSteps = [
    { step: 1, title: tr('Date & Time', 'თარიღი და დრო', 'Дата и время'), desc: tr('Choose your preferred time', 'აირჩიეთ სასურველი დრო', 'Выберите удобное время') },
    { step: 2, title: tr('Table Selection', 'მაგიდის შერჩევა', 'Выбор столика'), desc: tr('Pick a table on the 3D map', 'აირჩიეთ მაგიდა 3D რუკაზე', 'Выберите столик на 3D-карте') },
    { step: 3, title: tr('Pre-order', 'პრე-მენიუ', 'Предзаказ'), desc: tr('Pre-order your dishes', 'წინასწარ შეუკვეთეთ კერძები', 'Закажите блюда заранее') },
    { step: 4, title: tr('Confirmation', 'დადასტურება', 'Подтверждение'), desc: tr('Contact info & submit', 'საკონტაქტო ინფო', 'Контактные данные и отправка') },
  ];

  const isWizardStepDone = (step: number) => {
    if (step <= 2) return resStep >= 3;
    if (step === 3) return resStep >= 4;
    return false;
  };

  const isWizardStepActive = (step: number) => {
    if (resStep === 1) return step === 1;
    if (resStep === 3) return step === 3;
    if (resStep === 4) return step === 4;
    return false;
  };

  const wizardProgressPct = resStep === 1 ? 25 : resStep === 3 ? 75 : resStep === 4 ? 100 : 25;

  return (
    <section id="home" className="flex flex-col overflow-hidden bg-[#050505] text-white">

      {/* ══════════════════════════════════════════════════════════
          HERO
      ══════════════════════════════════════════════════════════ */}
      <div className="relative h-screen flex items-center justify-center overflow-hidden">
        <div className="absolute inset-0 z-0 overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-b from-[#050505]/80 via-[#050505]/50 to-[#050505] z-10" />
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,transparent_0%,#050505_100%)] z-10 opacity-90" />
          <img
            src={atmosphereImg}
            alt="Vankisi Restaurant Interior"
            className="w-full h-full object-cover opacity-70 animate-image-reveal"
          />
        </div>

        <div className="relative z-20 text-center px-6 max-w-5xl mb-24 w-full">
          <div className="mb-8 flex justify-center opacity-0 animate-fade-up-init" style={{ animationDelay: '0.2s' }}>
            <LogoSVG className="w-32 h-32 md:w-54 md:h-54 drop-shadow-[0_0_15px_rgba(174,137,94,0.3)]" />
          </div>

          <h2 className="text-[#ae895e] tracking-[0.5em] uppercase text-xs md:text-sm mb-6 opacity-0 animate-fade-up-init" style={{ animationDelay: '0.4s' }}>
            {tr('The Art of Taste', 'გემოს უმაღლესი ხელოვნება', 'Искусство вкуса')}
          </h2>

          <h1 className="text-6xl md:text-8xl font-light mb-8 tracking-wide text-white/95 opacity-0 animate-fade-up-init" style={{ letterSpacing: '0.05em', animationDelay: '0.6s' }}>
            {language === 'ka' ? <span className="font-header-geo">ვანკისი</span> : language === 'ru' ? <span className="font-header-en">ВАНКИСИ</span> : <span className="font-header-en">VANKISI</span>}
          </h1>

          <p className="text-lg md:text-xl text-white/50 mb-12 max-w-3xl mx-auto leading-loose font-light opacity-0 animate-fade-up-init" style={{ animationDelay: '0.8s' }}>
            {tr('Place where tradition meets taste', 'ადგილი, სადაც ტრადიცია ხვდება გემოს', 'Место, где традиции встречаются со вкусом')}
          </p>

          <div className="flex flex-col sm:flex-row gap-6 justify-center opacity-0 animate-fade-up-init" style={{ animationDelay: '1s' }}>
            <button
              onClick={scrollToReservation}
              className="group relative px-10 py-4 bg-[#ae895e] text-[#050505] overflow-hidden transition-all duration-300 cursor-pointer"
            >
              <span className="relative z-10 uppercase tracking-[0.2em] text-xs font-semibold flex items-center justify-center gap-3">
                {tr('Book a Table', 'მაგიდის დაჯავშნა', 'Забронировать столик')}
                <svg className="w-4 h-4 group-hover:translate-x-1 transition-transform duration-300" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
                </svg>
              </span>
              <div className="absolute inset-0 bg-white/20 scale-x-0 origin-left group-hover:scale-x-100 transition-transform duration-500 ease-out z-0" />
            </button>

            <Link
              to={`/${currentLang}/menu`}
              className="group px-10 py-4 border border-white/20 text-white/80 hover:border-[#ae895e] hover:text-[#ae895e] transition-all duration-500 uppercase tracking-[0.2em] text-xs font-medium flex items-center justify-center"
            >
              {tr('View Menu', 'მენიუს ნახვა', 'Смотреть меню')}
            </Link>
          </div>
        </div>

        <div className="absolute bottom-12 left-1/2 -translate-x-1/2 flex flex-col items-center gap-3 opacity-50 hover:opacity-100 transition-opacity cursor-pointer z-20" onClick={scrollToReservation}>
          <span className="text-[10px] uppercase tracking-[0.3em] text-[#ae895e]">Scroll</span>
          <div className="w-[1px] h-16 bg-gradient-to-b from-[#ae895e] to-transparent" />
        </div>
      </div>

      {/* ══════════════════════════════════════════════════════════
          RESERVATION SECTION (4-step)
      ══════════════════════════════════════════════════════════ */}
      <section id="reservation-section" ref={resSectionRef} className="py-32 px-8 bg-[#050505] relative border-b border-white/5">
        <div className="max-w-7xl mx-auto">
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-16 items-start">

            {/* Left: steps sidebar */}
            <AnimatedSection className="lg:col-span-5 pt-8">
              <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-medium block mb-6">
                {tr('Personal Journey', 'პერსონალური მოგზაურობა', 'Личное путешествие')}
              </span>
              <h3 className="text-4xl md:text-5xl font-light mb-8 leading-[1.3] text-white/95">
                {language === 'ka' ? (
                  <>დაგეგმეთ თქვენი <br /><span className="italic font-serif text-[#ae895e]">განსაკუთრებული</span> საღამო</>
                ) : language === 'ru' ? (
                  <>Спланируйте свой <br /><span className="italic font-serif text-[#ae895e]">незабываемый</span> вечер</>
                ) : (
                  <>Plan your <br /><span className="italic font-serif text-[#ae895e]">unforgettable</span> evening</>
                )}
              </h3>
              <p className="text-white/50 text-lg mb-12 leading-loose font-light">
                {tr(
                  'Our reservation system lets you pre-define every detail of your evening — from choosing the ideal table to an exclusive wine tasting.',
                  'ჩვენი ინტუიციური დაჯავშნის სისტემა გაძლევთ პრივილეგიას, წინასწარ განსაზღვროთ საღამოს ყოველი დეტალი — იდეალური მაგიდის შერჩევიდან, ექსკლუზიური ღვინის დეგუსტაციამდე.',
                  'Наша система бронирования позволяет заранее продумать каждую деталь вечера — от выбора идеального столика до эксклюзивной винной дегустации.',
                )}
              </p>

              <div className="space-y-6 border-l border-white/10 pl-6 relative">
                {/* animated gold progress line */}
                <div
                  className="absolute left-[-1px] top-0 w-[1px] bg-[#ae895e] transition-all duration-700"
                  style={{ height: `${wizardProgressPct}%` }}
                />
                {wizardSteps.map(s => (
                  <div key={s.step} className={`transition-opacity duration-300 ${isWizardStepDone(s.step) || isWizardStepActive(s.step) ? 'opacity-100' : 'opacity-30'}`}>
                    <h5 className={`text-sm font-medium tracking-widest uppercase mb-1 ${isWizardStepActive(s.step) ? 'text-[#ae895e]' : 'text-white'}`}>
                      {tr(`Step 0${s.step}`, `ნაბიჯი 0${s.step}`, `Шаг 0${s.step}`)}
                    </h5>
                    <p className="text-xs font-light text-white/50">{s.title}</p>
                  </div>
                ))}
              </div>
            </AnimatedSection>

            {/* Right: interactive box */}
            <AnimatedSection className="lg:col-span-7 relative" delay={200}>
              <div className="border border-white/5 bg-[#0a0a0a] p-8 md:p-12 relative overflow-hidden min-h-[600px] flex flex-col shadow-2xl">
                {/* top/bottom golden lines */}
                <div className="absolute top-0 left-0 w-full h-[1px] bg-gradient-to-r from-transparent via-[#ae895e]/30 to-transparent" />
                <div className="absolute bottom-0 left-0 w-full h-[1px] bg-gradient-to-r from-transparent via-[#ae895e]/30 to-transparent" />

                {/* Box header */}
                <div className="flex justify-between items-center mb-10 pb-6 border-b border-white/5">
                  <h4 className="text-xl font-light tracking-wide text-white/90">{stepTitles[resStep]}</h4>
                  {resStep > 1 && resStep !== 2 && (
                    <button
                      onClick={handleReservationBack}
                      className="text-xs text-white/40 hover:text-[#ae895e] uppercase tracking-widest flex items-center gap-2 transition-colors"
                    >
                      <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
                      </svg>
                      {tr('Back', 'უკან', 'Назад')}
                    </button>
                  )}
                </div>

                {/* ── Step 1: Date / Time / Guests (filters 3D availability) ── */}
                {resStep === 1 && (
                  <div className="flex-grow flex flex-col justify-center space-y-8 animate-fade-up-init">
                    <p className="text-white/45 text-sm font-light leading-relaxed">
                      {tr(
                        'Pick a date first — the 3D floor plan will only show tables available on that day.',
                        'ჯერ აირჩიეთ თარიღი — 3D რუკაზე გამოჩნდება მხოლოდ იმ დღეს ხელმისაწვდომი მაგიდები.',
                        'Сначала выберите дату — на 3D-плане будут показаны только столики, свободные в этот день.',
                      )}
                    </p>
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                      <div className="space-y-3">
                        <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                          {tr('Date', 'თარიღი', 'Дата')}
                        </label>
                        <div className="relative">
                          <svg className="absolute left-4 top-1/2 -translate-y-1/2 text-white/30 w-4 h-4 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                          </svg>
                          <input
                            type="date"
                            value={resDate}
                            onChange={e => setResDate(e.target.value)}
                            className="w-full min-w-0 block appearance-none bg-[#0a0a0a] border border-white/10 p-4 pl-12 text-white font-light focus:border-[#ae895e] outline-none transition-colors"
                          />
                        </div>
                      </div>
                      <div className="space-y-3">
                        <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                          {tr('Time', 'დრო', 'Время')}
                        </label>
                        <div className="relative">
                          <svg className="absolute left-4 top-1/2 -translate-y-1/2 text-white/30 w-4 h-4 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                          </svg>
                          <select
                            value={resTime}
                            onChange={e => setResTime(e.target.value)}
                            className="w-full bg-[#0a0a0a] border border-white/10 p-4 pl-12 text-white font-light focus:border-[#ae895e] outline-none transition-colors appearance-none"
                          >
                            {['10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00', '20:00', '21:00', '22:00'].map(t => (
                              <option key={t} value={t}>{t}</option>
                            ))}
                          </select>
                        </div>
                      </div>
                    </div>
                    <div className="space-y-3">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                        {tr('Guests', 'სტუმრების რაოდენობა', 'Количество гостей')}
                      </label>
                      <div className="relative">
                        <svg className="absolute left-4 top-1/2 -translate-y-1/2 text-white/30 w-4 h-4 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                        <input
                          type="number"
                          min={1}
                          max={99}
                          inputMode="numeric"
                          value={resGuests}
                          onChange={e => setResGuests(e.target.value)}
                          placeholder="2"
                          className="w-full bg-[#0a0a0a] border border-white/10 p-4 pl-12 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/25 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                        />
                      </div>
                    </div>
                    <ul className="space-y-3 pt-2 border-t border-white/5">
                      {[
                        tr('Browse both floors in interactive 3D', 'ორივე სართულის ნახვა 3D-ში', 'Просмотр обоих этажей в 3D'),
                        tr('See live availability for your date', 'თქვენი თარიღის ხელმისაწვდომობა', 'Доступность на выбранную дату'),
                        tr('Select one or more tables', 'ერთი ან რამდენიმე მაგიდის არჩევა', 'Выбор одного или нескольких столиков'),
                      ].map((item, i) => (
                        <li key={i} className="flex items-start gap-3 text-sm text-white/50 font-light">
                          <span className="text-[#ae895e] mt-0.5 shrink-0">◆</span>
                          {item}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                {/* Step 2: 3D map at /reservation/tables/:date */}

                {/* ── Step 3: Pre-order gateway ── */}
                {resStep === 3 && (
                  <div className="flex-grow flex flex-col items-center justify-center text-center animate-fade-up-init px-4">
                    <div className="w-20 h-20 rounded-full border border-[#ae895e]/30 flex items-center justify-center mb-8">
                      <svg className="w-8 h-8 text-[#ae895e]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z" />
                      </svg>
                    </div>
                    <h4 className="text-3xl font-light mb-4 text-white/95 tracking-wide">
                      {tr('Pre-order Menu', 'მენიუს წინასწარი შერჩევა', 'Предзаказ меню')}
                    </h4>
                    <p className="text-white/50 leading-loose text-sm max-w-sm mb-12 font-light">
                      {tr(
                        'You can pre-order dishes before confirming your reservation. Browse the full menu and add your favourites.',
                        'თქვენი ჯავშნის დასასრულებლად შეგიძლიათ წინასწარ შეუკვეთოთ კერძები. გთხოვთ, გადახვიდეთ სრულ მენიუში.',
                        'Перед подтверждением брони вы можете заранее заказать блюда. Откройте полное меню и добавьте любимые блюда.',
                      )}
                    </p>
                    <button
                      onClick={goToPreOrderMenu}
                      className="w-full max-w-xs bg-[#ae895e] text-[#050505] py-4 text-xs font-bold uppercase tracking-[0.2em] hover:bg-white transition-colors flex justify-center items-center gap-2 group"
                    >
                      {tr('Browse Full Menu', 'სრულ მენიუში გადასვლა', 'Открыть полное меню')}
                      <svg className="w-4 h-4 group-hover:translate-x-1 transition-transform" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
                      </svg>
                    </button>
                  </div>
                )}

                {/* ── Step 4: Contact info ── */}
                {resStep === 4 && (
                  <div className="flex-grow flex flex-col space-y-6 animate-fade-up-init">
                    {/* Pre-order summary */}
                    {preOrderItems.length > 0 && (
                      <div className="bg-[#ae895e]/5 border border-[#ae895e]/20 p-5 mb-2">
                        <h5 className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e] mb-3 border-b border-[#ae895e]/20 pb-2">
                          {tr(`Your selection (${preOrderCount} items):`, `თქვენი არჩევანი (${preOrderCount} კერძი):`, `Ваш выбор (${preOrderCount} блюд):`)}
                        </h5>
                        <div className="space-y-3 mb-4 max-h-40 overflow-y-auto custom-scrollbar pr-3">
                          {preOrderItems.map(item => (
                            <div key={item.id} className="flex justify-between items-start text-sm font-light text-white/80 border-b border-white/5 pb-3">
                              <div className="flex flex-col">
                                <span>{item.name}</span>
                                <span className="text-[10px] text-white/40 mt-1">{item.quantity} x {item.price}₾</span>
                              </div>
                              <span className="text-[#ae895e] font-medium whitespace-nowrap">{item.price * item.quantity}₾</span>
                            </div>
                          ))}
                        </div>
                        <div className="flex justify-between font-light border-t border-[#ae895e]/20 pt-3">
                          <span className="text-white/60">{tr('Total:', 'ჯამი:', 'Итого:')}</span>
                          <span className="text-[#ae895e] font-medium text-lg">{preOrderTotal}₾</span>
                        </div>
                      </div>
                    )}

                    <div className="space-y-3">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                        {tr('Full Name', 'სახელი და გვარი', 'Имя и фамилия')}
                      </label>
                      <input
                        type="text"
                        value={customerName}
                        onChange={(e) => setCustomerName(e.target.value)}
                        placeholder={tr('e.g. John Smith', 'მაგ: გიორგი მაისურაძე', 'напр. Иван Иванов')}
                        className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                      />
                    </div>
                    <div className="space-y-3">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                        {tr('Phone Number', 'ტელეფონის ნომერი', 'Номер телефона')}
                      </label>
                      <input
                        type="tel"
                        value={customerPhone}
                        onChange={(e) => setCustomerPhone(e.target.value)}
                        placeholder="+995 5__ __ __ __"
                        className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                      />
                    </div>
                    <div className="space-y-3">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                        {tr('Special Request (optional)', 'სპეციალური მოთხოვნა (სურვილისამებრ)', 'Особое пожелание (необязательно)')}
                      </label>
                      <textarea
                        value={specialRequest}
                        onChange={(e) => setSpecialRequest(e.target.value)}
                        placeholder={tr('Allergy, birthday...', 'ალერგია, დაბადების დღე...', 'Аллергия, день рождения...')}
                        className="w-full bg-transparent border-b border-white/20 pb-8 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20 resize-none"
                      />
                    </div>
                  </div>
                )}

                {resStep !== 3 && (
                  <div className="mt-10 pt-6 border-t border-white/5 text-center relative z-10">
                    <button
                      onClick={() => {
                        if (resStep === 1) {
                          goToTableMap();
                          return;
                        }
                        if (resStep < 4) setResStep(resStep + 1);
                        else navigate(`/${currentLang}/checkout`);
                      }}
                      disabled={resStep === 1 && !resDate}
                      className={`w-full cursor-pointer py-4 uppercase tracking-[0.3em] text-xs font-semibold flex items-center justify-center gap-3 transition-all duration-300 ${
                        resStep === 1 && !resDate
                          ? 'bg-white/5 text-white/20 cursor-not-allowed'
                          : 'bg-[#ae895e] text-[#050505] hover:bg-white'
                      }`}
                    >
                      {resStep === 1
                        ? tr('Open 3D Floor Plan', '3D რუკაზე გადასვლა', 'Открыть 3D-план зала')
                        : resStep === 4
                          ? tr('Continue to Payment', 'გაგრძელება გადახდაზე', 'Перейти к оплате')
                          : tr('Continue', 'გაგრძელება', 'Продолжить')}
                      <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                        <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
                      </svg>
                    </button>
                  </div>
                )}
              </div>
            </AnimatedSection>
          </div>
        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          ATMOSPHERE PREVIEW
      ══════════════════════════════════════════════════════════ */}
      <section className="py-32 px-8 bg-[#030303] relative border-b border-white/5">
        <div className="max-w-7xl mx-auto">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
            <AnimatedSection className="order-2 lg:order-1 relative">
              <div className="relative w-full aspect-[4/5] md:aspect-square max-w-lg mx-auto lg:mx-0">
                <div className="absolute top-0 right-0 w-[80%] h-[80%] border border-white/5 overflow-hidden">
                  <ImageWithSkeleton src={atmosphere1} className="opacity-80 hover:scale-105 transition-transform duration-1000" alt="Atmosphere Main" />
                </div>
                <div className="absolute bottom-0 left-0 w-[60%] h-[50%] border border-white/5 overflow-hidden shadow-2xl shadow-black">
                  <ImageWithSkeleton src={atmosphere2} className="opacity-90 hover:scale-105 transition-transform duration-1000" alt="Atmosphere Detail" />
                </div>
                <div className="absolute -top-4 -right-4 w-32 h-32 border-t border-r border-[#ae895e]/40 z-0"></div>
              </div>
            </AnimatedSection>

            <AnimatedSection className="order-1 lg:order-2 lg:pl-12" delay={200}>
              <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-medium block mb-6">{t('homeAtmosphere.subtitle')}</span>
              <h3 className="text-4xl md:text-5xl font-light mb-8 leading-[1.3] text-white/95">
                {t('homeAtmosphere.title').split(' ')[0]} <br /><span className="italic font-serif text-[#ae895e]">{t('homeAtmosphere.title').split(' ')[1] || ''}</span>
              </h3>
              <p className="text-white/50 text-lg mb-10 leading-loose font-light">
                {t('homeAtmosphere.desc')}
              </p>
              <button
                onClick={() => handleNavClick('atmosphere')}
                className="flex items-center gap-3 text-xs uppercase tracking-[0.2em] text-white/80 hover:text-[#ae895e] transition-colors pb-2 border-b border-transparent hover:border-[#ae895e] cursor-pointer"
              >
                {t('homeAtmosphere.btn')}
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
                </svg>
              </button>
            </AnimatedSection>
          </div>
        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          EXCLUSIVE EXPERIENCES
      ══════════════════════════════════════════════════════════ */}
      <section className="py-32 px-8 relative bg-[#030303] border-b border-white/5">
        <div className="max-w-7xl mx-auto">
          <AnimatedSection className="text-center mb-20">
            <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-medium block mb-6">
              {tr('Events & Offers', 'მოვლენები & შეთავაზებები', 'События и предложения')}
            </span>
            <h3 className="text-4xl md:text-5xl font-light text-white/95 mb-6">
              {language === 'ka' ? (
                <>ექსკლუზიური <span className="italic font-serif text-[#ae895e]">გამოცდილება</span></>
              ) : language === 'ru' ? (
                <>Эксклюзивные <span className="italic font-serif text-[#ae895e]">впечатления</span></>
              ) : (
                <>Exclusive <span className="italic font-serif text-[#ae895e]">Experiences</span></>
              )}
            </h3>
            <p className="text-white/40 max-w-2xl mx-auto leading-loose font-light">
              {tr(
                'Discover more than just dinner. Vankisi offers unforgettable evenings, live music and personalised service.',
                'აღმოაჩინეთ მეტი ვიდრე უბრალოდ ვახშამი. ვანკისი გთავაზობთ დაუვიწყარ საღამოებს, ცოცხალ მუსიკასა და პერსონალიზებულ სერვისს.',
                'Откройте для себя нечто большее, чем просто ужин. Vankisi дарит незабываемые вечера, живую музыку и индивидуальный сервис.',
              )}
            </p>
          </AnimatedSection>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 lg:gap-12">
            {[
              {
                delay: 100,
                className: '',
                img: photoshoot,
                alt: 'Georgian Dining',
                tag: tr('Taste & Aesthetics', 'გემო და ესთეტიკა', 'Вкус и эстетика'),
                title: tr('Georgian Cuisine, Elevated', 'ქართული სამზარეულო ახალ დონეზე', 'Грузинская кухня на новом уровне'),
                desc: tr(
                  'Traditional Georgian dishes reimagined with a modern touch, served in an elegant setting with carefully selected wines.',
                  'ტრადიციული ქართული კერძები თანამედროვე შესრულებით, დახვეწილ გარემოში და საგულდაგულოდ შერჩეულ ღვინოსთან.',
                  'Традиционные грузинские блюда в современном исполнении, поданные в изысканной обстановке с тщательно подобранными винами.',
                ),
              },
              {
                delay: 300,
                className: 'mt-0 md:mt-12',
                img: khinkali,
                alt: "Khinkali Experience",
                tag: tr('Tradition', 'ტრადიცია', 'Традиция'),
                title: tr('Khinkali, Perfected', 'ხინკალი, სრულყოფილებაში', 'Хинкали в совершенстве'),
                desc: tr(
                  'One of the pillars of Georgian cuisine - crafted with precision, experience, and deep respect for flavor.',
                  'ქართული კულინარიის ერთ-ერთი მთავარი სიმბოლო - დამზადებული სიზუსტით, გამოცდილებით და გემოს სრული პატივისცემით.',
                  'Один из главных символов грузинской кухни — приготовленный с точностью, опытом и глубоким уважением ко вкусу.',
                ),
              },
              {
                delay: 500,
                className: 'mt-0 md:mt-24',
                img: 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&q=80&w=800',
                alt: 'Private Dining',
                tag: tr('Private Dining', 'დახურული სივრცე', 'Приватный зал'),
                title: tr('Private Space', 'პრივატული სივრცე', 'Отдельное пространство'),
                desc: tr(
                  'Reserve a private space for up to 16 guests with a tailored menu and fully personalized service.',
                  'დაჯავშნეთ დახურული სივრცე მაქსიმუმ 16 სტუმრისთვის — ინდივიდუალური მენიუ და სრულად პერსონალური მომსახურება.',
                  'Забронируйте приватное пространство до 16 гостей с индивидуальным меню и полностью персональным обслуживанием.',
                ),
              },
            ].map((exp, i) => (
              <AnimatedSection key={i} delay={exp.delay} className={`group cursor-pointer ${exp.className}`}>
                <div className="relative aspect-[3/4] overflow-hidden border border-white/5 group-hover:border-[#ae895e]/30 transition-colors duration-500">
                  <img
                    src={exp.img}
                    alt={exp.alt}
                    className="w-full h-full object-cover transition-transform duration-1000 group-hover:scale-105 opacity-60 group-hover:opacity-40"
                  />
                  <div className="absolute inset-0 bg-gradient-to-t from-[#050505] via-[#050505]/40 to-transparent" />
                  <div className="absolute inset-0 p-8 flex flex-col justify-end transform transition-transform duration-500 translate-y-4 group-hover:translate-y-0">
                    <span className="text-[#ae895e] text-[10px] uppercase tracking-[0.3em] font-bold mb-3 block">{exp.tag}</span>
                    <h4 className="text-2xl font-light text-white/95 mb-3 tracking-wide">{exp.title}</h4>
                    <p className="text-sm text-white/50 font-light leading-relaxed transition-all duration-1000 opacity-100 md:opacity-0 md:group-hover:opacity-100 delay-[1200ms] md:delay-100">
                      {exp.desc}
                    </p>
                  </div>
                </div>
              </AnimatedSection>
            ))}
          </div>
        </div>
      </section>

      {/* ══════════════════════════════════════════════════════════
          QUICK MENU PREVIEW
      ══════════════════════════════════════════════════════════ */}
      <section className="py-32 px-8 relative bg-[#050505]">
        <div className="max-w-7xl mx-auto">
          <AnimatedSection className="flex flex-col md:flex-row justify-between items-end mb-20 gap-8">
            <div>
              <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-medium block mb-6">
                {tr('Gastronomy', 'გასტრონომია', 'Гастрономия')}
              </span>
              <h3 className="text-4xl md:text-5xl font-light text-white/95">
                {language === 'ka' ? (
                  <>ჩვენი შეფ-მზარეულის <br /><span className="italic font-serif text-[#ae895e]">შედევრები</span></>
                ) : language === 'ru' ? (
                  <>Шедевры нашего <br /><span className="italic font-serif text-[#ae895e]">шеф-повара</span></>
                ) : (
                  <>Our chef's <br /><span className="italic font-serif text-[#ae895e]">masterpieces</span></>
                )}
              </h3>
            </div>
            <Link
              to={`/${currentLang}/menu`}
              className="flex items-center gap-3 text-xs uppercase tracking-[0.2em] text-white/60 hover:text-[#ae895e] transition-colors pb-2 border-b border-transparent hover:border-[#ae895e]"
            >
              {tr('View Full Menu', 'სრული მენიუს ხილვა', 'Смотреть полное меню')}
              <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
              </svg>
            </Link>
          </AnimatedSection>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-12 lg:gap-16">
            {[
              {
                title: tr('Signature Khachapuri', 'საფირმო ხაჭაპური', 'Фирменный хачапури'),
                price: '35₾',
                desc: tr('A blend of three cheeses, golden crust and melted butter.', 'სამი სახეობის ყველის მიქსი, ოქროსფერი ქერქი და მდნარი კარაქი.', 'Микс из трёх сыров, золотистая корочка и растопленное масло.'),
                img: 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&q=80&w=800',
              },
              {
                title: tr('Veal Chakapuli', 'ხბოს ჩაქაფული', 'Чакапули из телятины'),
                price: '48₾',
                desc: tr('Young spring herbs, white wine and cherry-plum sauce.', 'გაზაფხულის ნორჩი მწვანილით, თეთრი ღვინითა და ტყემლით შეზავებული.', 'Молодая весенняя зелень, белое вино и соус из ткемали.'),
                img: 'https://images.unsplash.com/photo-1514516874246-818274d82eb1?auto=format&fit=crop&q=80&w=800',
              },
              {
                title: tr('Premium Assortment', 'პრემიუმ ასორტი', 'Премиум ассорти'),
                price: '55₾',
                desc: tr('A masterfully curated board of finest Georgian cheeses and charcuterie.', 'საუკეთესო ქართული ყველისა და ხორცის ოსტატურად შერჩეული დაფა.', 'Мастерски составленная доска из лучших грузинских сыров и мясных деликатесов.'),
                img: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&q=80&w=800',
              },
            ].map((dish, i) => (
              <AnimatedSection key={i} delay={i * 200} className="group cursor-pointer">
                <Link to={`/${currentLang}/menu`}>
                  <div className="overflow-hidden mb-8 aspect-[3/4] relative bg-[#0a0a0a]">
                    <img
                      src={dish.img}
                      alt={dish.title}
                      className="w-full h-full object-cover transition-transform duration-1000 group-hover:scale-110 opacity-80 group-hover:opacity-100"
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-[#050505] via-transparent to-transparent opacity-80" />
                    <div className="absolute bottom-6 left-6 right-6 flex justify-between items-end">
                      <span className="text-[#ae895e] font-light text-xl tracking-wider">{dish.price}</span>
                      <div className="w-8 h-[1px] bg-[#ae895e] transform origin-right scale-x-0 group-hover:scale-x-100 transition-transform duration-500" />
                    </div>
                  </div>
                  <h4 className="text-2xl font-light mb-4 text-white/90 group-hover:text-[#ae895e] transition-colors tracking-wide">{dish.title}</h4>
                  <p className="text-white/40 leading-loose font-light text-sm">{dish.desc}</p>
                </Link>
              </AnimatedSection>
            ))}
          </div>
        </div>
      </section>
    </section>
  );
};

export default Header;