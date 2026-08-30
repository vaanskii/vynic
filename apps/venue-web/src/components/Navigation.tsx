import { useState, useEffect, useRef } from 'react';
import { Link, useParams, useNavigate, useLocation } from 'react-router-dom';
import { useLanguage, LANGUAGES, type Language } from '../contexts/LanguageContext';
import { useAuth } from '../contexts/AuthContext';
import { authService } from '../services/api';
import { isReservationTablesPath } from '../routes/reservation';
import { isComingSoonMode } from '../config/siteMode';

// ─── Micro icon helpers ────────────────────────────────────────────────────────
const IconGlobe = ({ size = 16 }: { size?: number }) => (
  <svg width={size} height={size} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.7}>
    <circle cx="12" cy="12" r="10" />
    <path strokeLinecap="round" strokeLinejoin="round" d="M2 12h20M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z" />
  </svg>
);
const IconUser = ({ size = 20 }: { size?: number }) => (
  <svg width={size} height={size} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.7}>
    <path strokeLinecap="round" strokeLinejoin="round" d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2M12 11a4 4 0 100-8 4 4 0 000 8z" />
  </svg>
);
const IconX = ({ size = 24 }: { size?: number }) => (
  <svg width={size} height={size} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
    <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
  </svg>
);
const IconArrow = ({ size = 16 }: { size?: number }) => (
  <svg width={size} height={size} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
    <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
  </svg>
);

// ─── Inline Logo SVG ────────────────────────────────────────────────────────
const LogoSVG = ({ className }: { className?: string }) => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" className={className}>
    <path fill="#ae895e" d="M133 151L151 167Q167 177 187 184L226 195L231 195L236 197L241 197L246 199L264 202L268 204L272 204L302 214Q329 226 348 248L350 251L363 269L376 301L377 308L382 321L382 325L384 328L391 354L393 357L405 396L405 401L407 408L408 434L407 435L407 445L406 446L405 457L398 478L397 477L399 466L399 439L395 419L393 416L393 413L391 410L391 407L386 395L384 385L382 383L373 353L368 342L366 333L361 322L361 319L359 317L359 314Q347 286 327 268L324 266Q309 252 288 245L267 239L256 238L250 236L245 236L239 234L233 234L208 229L192 224L170 213L167 213Q168 210 165 211L147 196L135 174Q136 167 133 165L133 151Z" />
    <path fill="#ae895e" d="M149 228L151 229Q150 232 153 231L171 245L198 256L214 259L218 261L225 261L230 263L247 265L257 268L263 268L293 277L313 288L328 303Q341 317 347 339L336 328L314 314L296 307L265 300L257 300L245 297L228 295L201 288Q178 280 163 264Q150 250 149 228Z" />
    <path fill="#ae895e" d="M176 299L198 311L218 318L238 322L245 322L272 327L278 327L297 331L317 339L332 350L332 352Q335 351 334 354L345 368L356 390L361 403L361 406L384 463L384 466L402 510L402 513L409 528L412 539L416 546L416 549L425 570L425 573Q428 574 427 571L509 367L512 356L512 350L506 339L495 334L487 334L488 329L586 329L586 334L584 334Q567 337 558 349L548 366Q545 378 539 387L537 395L516 442L516 445L514 447L507 466L505 468L505 471L500 479L498 487Q489 501 484 520L482 522L471 551L457 581L432 642L430 644L428 644L417 644L415 643Q413 645 412 643L411 638L404 623L404 620L393 595L393 592L388 582L388 579L386 577L384 568L382 566L373 543L373 540L371 538L363 515L359 508L359 505L354 495L352 487L345 472L345 469L331 436L323 413L311 386L302 373Q299 374 300 372L295 368Q296 365 294 366L283 359L264 352L235 345L229 345L216 341L201 333L186 320L184 317L176 304L176 299Z" />
  </svg>
);

// ─── Auth drawer labels ───────────────────────────────────────────────────────
const authLabels = {
  en: {
    login: 'Sign In', register: 'Create Account',
    phone: 'Phone Number', email: 'Email', phoneOrEmail: 'Phone or Email', pass: 'Password',
    firstName: 'First Name', lastName: 'Last Name',
    loginBtn: 'Sign In', regBtn: 'Complete Registration',
    noAccount: "Don't have an account?", haveAccount: 'Already have an account?',
    switchReg: 'Register Here', switchLog: 'Sign In',
    logout: 'Sign Out',
    profile: 'My Profile',
  },
  ka: {
    login: 'ავტორიზაცია', register: 'რეგისტრაცია',
    phone: 'ტელეფონის ნომერი', email: 'ელ. ფოსტა', phoneOrEmail: 'ტელეფონი ან ელ. ფოსტა', pass: 'პაროლი',
    firstName: 'სახელი', lastName: 'გვარი',
    loginBtn: 'შესვლა', regBtn: 'რეგისტრაცია',
    noAccount: 'არ გაქვთ ანგარიში?', haveAccount: 'უკვე გაქვთ ანგარიში?',
    switchReg: 'დარეგისტრირდით', switchLog: 'გაიარეთ ავტორიზაცია',
    logout: 'გასვლა',
    profile: 'ჩემი პროფილი',
  },
  ru: {
    login: 'Вход', register: 'Регистрация',
    phone: 'Номер телефона', email: 'Эл. почта', phoneOrEmail: 'Телефон или email', pass: 'Пароль',
    firstName: 'Имя', lastName: 'Фамилия',
    loginBtn: 'Войти', regBtn: 'Завершить регистрацию',
    noAccount: 'Нет аккаунта?', haveAccount: 'Уже есть аккаунт?',
    switchReg: 'Зарегистрироваться', switchLog: 'Войти',
    logout: 'Выйти',
    profile: 'Мой профиль',
  },
};

const LANG_LABEL: Record<Language, string> = { en: 'EN', ka: 'KA', ru: 'RU' };
const LANG_NAME: Record<Language, string> = { en: 'English', ka: 'ქართული', ru: 'Русский' };

const Navigation = () => {
  const { language, setLanguage, t } = useLanguage();
  const { user, logout } = useAuth();
  const params = useParams<{ lang: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const isMap3D = isReservationTablesPath(location.pathname);
  const currentLang = params.lang || language;

  const isActive = (href: string) => {
    const normalize = (path: string) => path.endsWith('/') ? path.slice(0, -1) : path;
    const current = normalize(location.pathname);
    const target = normalize(href);
    return current === target;
  };

  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);

  // Language dropdown
  const [isLangOpen, setIsLangOpen] = useState(false);
  const langRef = useRef<HTMLDivElement>(null);
  const langRefMobile = useRef<HTMLDivElement>(null);

  const changeLanguage = (lang: Language) => {
    setIsLangOpen(false);
    if (lang !== language) setLanguage(lang);
  };

  // Auth drawer
  const [isAuthOpen, setIsAuthOpen] = useState(false);
  const [authMode, setAuthMode] = useState<'login' | 'register'>('login');
  const [authLoginId, setAuthLoginId] = useState('');
  const [authPhone, setAuthPhone] = useState('');
  const [authEmail, setAuthEmail] = useState('');
  const [authPass, setAuthPass] = useState('');
  const [authFirstName, setAuthFirstName] = useState('');
  const [authLastName, setAuthLastName] = useState('');
  const [authError, setAuthError] = useState('');
  const [authLoading, setAuthLoading] = useState(false);
  const drawerRef = useRef<HTMLDivElement>(null);

  const al = authLabels[language];

  // Scroll effect
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 50);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  // Close language dropdown on outside click / Escape
  useEffect(() => {
    if (!isLangOpen) return;
    const onPointer = (e: PointerEvent) => {
      const target = e.target as Node;
      const inDesktop = langRef.current?.contains(target);
      const inMobile = langRefMobile.current?.contains(target);
      if (!inDesktop && !inMobile) {
        setIsLangOpen(false);
      }
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsLangOpen(false);
    };
    document.addEventListener('pointerdown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onPointer);
      document.removeEventListener('keydown', onKey);
    };
  }, [isLangOpen]);

  // Lock body scroll when overlays are open
  useEffect(() => {
    document.body.style.overflow = (isMenuOpen || isAuthOpen) ? 'hidden' : '';
    return () => { document.body.style.overflow = ''; };
  }, [isMenuOpen, isAuthOpen]);

  // Reset auth form on mode change
  useEffect(() => {
    setAuthError('');
    setAuthLoginId('');
    setAuthPhone('');
    setAuthEmail('');
    setAuthPass('');
    setAuthFirstName('');
    setAuthLastName('');
  }, [authMode, isAuthOpen]);

  const handleLogout = async () => {
    await logout();
    setIsMenuOpen(false);
    setIsAuthOpen(false);
  };

  const scrollToReservation = (e?: React.MouseEvent) => {
    e?.preventDefault();
    setIsMenuOpen(false);
    if (window.location.pathname === `/${currentLang}` || window.location.pathname === `/${currentLang}/` || window.location.pathname === '/' || window.location.pathname === '') {
      document.getElementById('reservation-section')?.scrollIntoView({ behavior: 'smooth' });
    } else {
      navigate(`/${currentLang}`);
      setTimeout(() => {
        document.getElementById('reservation-section')?.scrollIntoView({ behavior: 'smooth' });
      }, 150);
    }
  };

  const handleAuthSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setAuthError('');
    setAuthLoading(true);
    try {
      if (authMode === 'login') {
        await authService.signin({ identifier: authLoginId.trim(), password: authPass });
      } else {
        await authService.signup({
          phone: authPhone.trim(),
          email: authEmail.trim(),
          password: authPass,
          firstName: authFirstName.trim() || undefined,
          lastName: authLastName.trim() || undefined,
        });
      }
      // Reload to refresh auth state from AuthContext
      window.location.reload();
    } catch (err: unknown) {
      const message = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      setAuthError(message || (authMode === 'login'
        ? (language === 'ka' ? 'ავტორიზაცია ვერ მოხერხდა' : language === 'ru' ? 'Не удалось войти' : 'Login failed')
        : (language === 'ka' ? 'რეგისტრაცია ვერ მოხერხდა' : language === 'ru' ? 'Не удалось зарегистрироваться' : 'Registration failed')));
    } finally {
      setAuthLoading(false);
    }
  };

  const navItems = isComingSoonMode
    ? [{ id: 'home', name: t('nav.home'), href: `/${currentLang}` }]
    : [
        { id: 'home', name: t('nav.home'), href: `/${currentLang}` },
        { id: 'menu', name: t('nav.menu'), href: `/${currentLang}/menu` },
        { id: 'atmosphere', name: t('nav.atmosphere'), href: `/${currentLang}/atmosphere` },
        { id: 'contact', name: t('nav.contact'), href: `/${currentLang}/contact` },
      ];

  return (
    <>
      {/* ── Main navbar ────────────────────────────────────────────────────── */}
      <nav
        id="site-nav"
        className={`fixed w-full z-50 flex items-center transition-all duration-500 ${
          scrolled || isMap3D
            ? 'border-b border-white/5 bg-[#050505]/95 py-3 min-h-[64px] shadow-2xl backdrop-blur-md'
            : 'bg-transparent py-4 sm:py-6 min-h-[64px] sm:min-h-[72px]'
        }`}
      >
        <div className="max-w-7xl mx-auto w-full px-4 sm:px-6 lg:px-8 flex justify-between items-center gap-2 sm:gap-4 min-w-0">

          {/* Logo */}
          <Link
            to={`/${currentLang}`}
            className="flex items-center gap-2 sm:gap-4 group cursor-pointer shrink-0 min-w-0"
            onClick={() => setIsMenuOpen(false)}
          >
            <LogoSVG className="w-9 h-9 sm:w-10 sm:h-10 lg:w-12 lg:h-12 drop-shadow-lg transition-transform duration-300 group-hover:scale-110 shrink-0" />
            <span className="text-lg sm:text-xl lg:text-2xl font-light tracking-[0.2em] sm:tracking-[0.3em] uppercase hidden sm:block text-white/90 group-hover:text-[#ae895e] transition-colors duration-300 truncate">
              {language === 'ka' ? <span className="font-header-geo">ვანკისი</span> : <span className="font-header-en">VANKISI</span>}
            </span>
          </Link>

          {/* Desktop nav links */}
          <div className="hidden lg:flex items-center justify-center gap-4 xl:gap-8 2xl:gap-10 text-[10px] xl:text-xs font-medium tracking-[0.15em] xl:tracking-[0.2em] uppercase text-white/60 flex-1 min-w-0 px-2">
            {navItems.map(item => {
              const active = isActive(item.href);
              return (
                <Link
                  key={item.id}
                  to={item.href}
                  className={`hover:text-[#ae895e] transition-colors duration-300 cursor-pointer ${active ? 'text-[#ae895e]' : ''}`}
                >
                  {item.name}
                </Link>
              );
            })}
          </div>

          {/* Desktop right: lang globe + user + book */}
          <div className="hidden lg:flex items-center gap-3 xl:gap-6 border-l border-white/10 pl-4 xl:pl-8 ml-1 shrink-0">
            {/* Language dropdown */}
            <div className="relative" ref={langRef}>
              <button
                onClick={() => setIsLangOpen((o) => !o)}
                className="flex items-center gap-2 hover:text-[#ae895e] transition-colors group cursor-pointer"
                title="Change Language"
                aria-haspopup="listbox"
                aria-expanded={isLangOpen}
              >
                <span className="text-white/40 group-hover:text-[#ae895e] transition-colors">
                  <IconGlobe size={16} />
                </span>
                <span className="text-xs font-bold tracking-widest text-[#ae895e]">
                  {LANG_LABEL[language]}
                </span>
                <svg
                  className={`w-3 h-3 text-white/40 transition-transform duration-300 ${isLangOpen ? 'rotate-180' : ''}`}
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth={2}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
                </svg>
              </button>

              <div
                role="listbox"
                className={`absolute right-0 top-full mt-3 min-w-[150px] origin-top-right border border-white/10 bg-[#0a0a0a]/95 backdrop-blur-md shadow-2xl transition-all duration-200 ${
                  isLangOpen
                    ? 'opacity-100 translate-y-0 pointer-events-auto'
                    : 'opacity-0 -translate-y-1 pointer-events-none'
                }`}
              >
                {LANGUAGES.map((lng) => (
                  <button
                    key={lng}
                    role="option"
                    aria-selected={language === lng}
                    onClick={() => changeLanguage(lng)}
                    className={`flex w-full items-center justify-between gap-4 px-4 py-3 text-left text-xs uppercase tracking-[0.2em] transition-colors cursor-pointer ${
                      language === lng
                        ? 'bg-[#ae895e]/10 text-[#ae895e]'
                        : 'text-white/60 hover:bg-white/5 hover:text-white'
                    }`}
                  >
                    <span className="font-medium">{LANG_NAME[lng]}</span>
                    <span className="text-[10px] font-bold tracking-widest opacity-70">{LANG_LABEL[lng]}</span>
                  </button>
                ))}
              </div>
            </div>

            {/* User icon */}
            {!isComingSoonMode && (user ? (
              <div className="flex items-center gap-4">
                <Link
                  to={`/${currentLang}/profile`}
                  className="text-white/60 hover:text-[#ae895e] transition-colors cursor-pointer"
                  title={al.profile}
                >
                  <IconUser size={20} />
                </Link>
                <button
                  onClick={handleLogout}
                  className="hidden xl:inline text-[10px] uppercase tracking-[0.2em] text-white/40 hover:text-[#ae895e] transition-colors cursor-pointer"
                >
                  {al.logout}
                </button>
              </div>
            ) : (
              <button
                onClick={() => setIsAuthOpen(true)}
                className="text-white/60 hover:text-[#ae895e] transition-colors cursor-pointer"
                title={al.login}
              >
                <IconUser size={20} />
              </button>
            ))}

            {/* Book table button */}
            {!isComingSoonMode && (
            <button
              onClick={scrollToReservation}
              className="px-3 xl:px-6 2xl:px-8 py-2 xl:py-3 border border-[#ae895e]/30 text-[#ae895e] hover:bg-[#ae895e] hover:text-black transition-all duration-500 text-[10px] xl:text-xs font-semibold uppercase tracking-[0.15em] xl:tracking-[0.2em] whitespace-nowrap cursor-pointer"
            >
              {t('nav.reservations')}
            </button>
            )}
          </div>

          {/* Mobile / tablet: lang + user + hamburger */}
          <div className="lg:hidden flex items-center gap-3 sm:gap-5 shrink-0">
            <div className="relative" ref={langRefMobile}>
              <button
                onClick={() => setIsLangOpen((o) => !o)}
                className="flex items-center gap-1 text-xs font-bold tracking-widest text-[#ae895e] cursor-pointer"
                aria-haspopup="listbox"
                aria-expanded={isLangOpen}
              >
                {LANG_LABEL[language]}
                <svg
                  className={`w-3 h-3 transition-transform duration-300 ${isLangOpen ? 'rotate-180' : ''}`}
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth={2}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
                </svg>
              </button>

              <div
                role="listbox"
                className={`absolute right-0 top-full mt-3 min-w-[150px] origin-top-right border border-white/10 bg-[#0a0a0a]/95 backdrop-blur-md shadow-2xl transition-all duration-200 ${
                  isLangOpen
                    ? 'opacity-100 translate-y-0 pointer-events-auto'
                    : 'opacity-0 -translate-y-1 pointer-events-none'
                }`}
              >
                {LANGUAGES.map((lng) => (
                  <button
                    key={lng}
                    role="option"
                    aria-selected={language === lng}
                    onClick={() => changeLanguage(lng)}
                    className={`flex w-full items-center justify-between gap-4 px-4 py-3 text-left text-xs uppercase tracking-[0.2em] transition-colors cursor-pointer ${
                      language === lng
                        ? 'bg-[#ae895e]/10 text-[#ae895e]'
                        : 'text-white/60 hover:bg-white/5 hover:text-white'
                    }`}
                  >
                    <span className="font-medium">{LANG_NAME[lng]}</span>
                    <span className="text-[10px] font-bold tracking-widest opacity-70">{LANG_LABEL[lng]}</span>
                  </button>
                ))}
              </div>
            </div>
            {!isComingSoonMode && (user ? (
              <Link to={`/${currentLang}/profile`} className="text-white/70 hover:text-[#ae895e] transition-colors cursor-pointer">
                <IconUser size={22} />
              </Link>
            ) : (
              <button
                onClick={() => setIsAuthOpen(true)}
                className="text-white/70 hover:text-[#ae895e] transition-colors cursor-pointer"
              >
                <IconUser size={22} />
              </button>
            ))}
            {!isComingSoonMode && (
            <button
              onClick={() => setIsMenuOpen(true)}
              className="text-white/80 hover:text-[#ae895e] transition-colors cursor-pointer"
              aria-label="Open menu"
            >
              <svg className="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            </button>
            )}
          </div>
        </div>
      </nav>

      {/* ── Mobile full-screen overlay ───────────────────────────────────── */}
      {!isComingSoonMode && (
      <div
        className={`fixed inset-0 z-[60] bg-[#050505] transition-opacity duration-500 ${isMenuOpen ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'
          }`}
      >
        <div className="flex flex-col items-center justify-center h-full gap-10 text-xl font-light uppercase tracking-[0.3em] relative">
          <button
            className="absolute cursor-pointer top-8 right-8 text-white/50 hover:text-[#ae895e] transition-colors"
            onClick={() => setIsMenuOpen(false)}
          >
            <IconX size={36} />
          </button>

          <LogoSVG className="w-20 h-20 mb-8 opacity-80" />

          {navItems.map(item => {
            const active = isActive(item.href);
            return (
              <Link
                key={item.id}
                to={item.href}
                onClick={() => setIsMenuOpen(false)}
                className={`transition-colors duration-300 ${active ? 'text-[#ae895e]' : 'text-white/80 hover:text-[#ae895e]'}`}
              >
                {item.name}
              </Link>
            );
          })}

          <button
            onClick={scrollToReservation}
            className="text-white/80 hover:text-[#ae895e] transition-colors duration-300 uppercase"
          >
            {t('nav.reservations')}
          </button>
        </div>
      </div>
      )}

      {/* ── Auth drawer overlay ──────────────────────────────────────────── */}
      {!isComingSoonMode && (
      <>
      <div
        className={`fixed inset-0 bg-black/60 backdrop-blur-sm z-[80] transition-opacity duration-500 ${isAuthOpen ? 'opacity-100 pointer-events-auto' : 'opacity-0 pointer-events-none'
          }`}
        onClick={() => setIsAuthOpen(false)}
      />

      {/* ── Auth drawer panel ────────────────────────────────────────────── */}
      <div
        ref={drawerRef}
        className={`fixed top-0 right-0 h-full w-full max-w-md bg-[#0a0a0a] border-l border-white/10 z-[90] transform transition-transform duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] flex flex-col ${isAuthOpen ? 'translate-x-0' : 'translate-x-full'
          }`}
      >
        {/* Drawer header */}
        <div className="p-6 border-b border-white/5 flex justify-between items-center">
          <div className="flex items-center gap-3 text-[#ae895e]">
            <IconUser size={20} />
            <h3 className="text-sm font-medium tracking-[0.2em] uppercase">
              {authMode === 'login' ? al.login : al.register}
            </h3>
          </div>
          <button onClick={() => setIsAuthOpen(false)} className="text-white/50 hover:text-white transition-colors cursor-pointer">
            <IconX size={24} />
          </button>
        </div>

        {/* Drawer body */}
        <div className="flex-grow overflow-y-auto custom-scrollbar p-8 flex flex-col justify-center">
          {/* Logo mark */}
          <div className="w-16 h-16 rounded-full border border-[#ae895e]/30 flex items-center justify-center mx-auto mb-8">
            <LogoSVG className="w-10 h-10 opacity-80" />
          </div>

          <h2 className="text-3xl font-light text-center mb-10 text-white/90">
            {authMode === 'login' ? al.login : al.register}
          </h2>

          <form onSubmit={handleAuthSubmit} className="space-y-6">
            {/* Register-only: first + last name */}
            {authMode === 'register' && (
              <>
                <div className="space-y-2">
                  <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">{al.firstName}</label>
                  <input
                    type="text"
                    value={authFirstName}
                    onChange={e => setAuthFirstName(e.target.value)}
                    className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                    placeholder="მაგ: გიორგი"
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">{al.lastName}</label>
                  <input
                    type="text"
                    value={authLastName}
                    onChange={e => setAuthLastName(e.target.value)}
                    className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                    placeholder="მაგ: მაისურაძე"
                  />
                </div>
              </>
            )}

            {/* Login: phone or email */}
            {authMode === 'login' && (
              <div className="space-y-2">
                <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">{al.phoneOrEmail}</label>
                <input
                  type="text"
                  value={authLoginId}
                  onChange={e => setAuthLoginId(e.target.value)}
                  required
                  autoComplete="username"
                  className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                  placeholder="+995 599 98 93 76 or you@email.com"
                />
              </div>
            )}

            {/* Register: phone + email */}
            {authMode === 'register' && (
              <>
                <div className="space-y-2">
                  <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">{al.phone}</label>
                  <input
                    type="tel"
                    value={authPhone}
                    onChange={e => setAuthPhone(e.target.value)}
                    required
                    autoComplete="tel"
                    className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                    placeholder="+995 599 98 93 76"
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">{al.email}</label>
                  <input
                    type="email"
                    value={authEmail}
                    onChange={e => setAuthEmail(e.target.value)}
                    required
                    autoComplete="email"
                    className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                    placeholder="you@email.com"
                  />
                </div>
              </>
            )}

            {/* Password */}
            <div className="space-y-2">
              <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">{al.pass}</label>
              <input
                type="password"
                value={authPass}
                onChange={e => setAuthPass(e.target.value)}
                required
                className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/20"
                placeholder="••••••••"
              />
            </div>

            {/* Error message */}
            {authError && (
              <p className="text-red-400/80 text-xs tracking-wide py-2 border border-red-500/20 px-3 bg-red-900/10">
                {authError}
              </p>
            )}

            {/* Submit */}
            <button
              type="submit"
              disabled={authLoading}
              className="w-full py-4 mt-4 bg-[#ae895e] text-black uppercase tracking-[0.2em] text-xs font-bold hover:bg-white transition-colors flex items-center justify-center gap-3 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {authLoading
                ? (language === 'ka' ? 'გთხოვთ დაელოდეთ...' : language === 'ru' ? 'Пожалуйста, подождите...' : 'Please wait...')
                : (authMode === 'login' ? al.loginBtn : al.regBtn)}
              {!authLoading && <IconArrow size={16} />}
            </button>
          </form>

          {/* Switch mode */}
          <div className="mt-8 text-center border-t border-white/5 pt-6">
            <p className="text-white/50 text-sm font-light mb-3">
              {authMode === 'login' ? al.noAccount : al.haveAccount}
            </p>
            <button
              onClick={() => setAuthMode(authMode === 'login' ? 'register' : 'login')}
              className="text-[#ae895e] text-xs uppercase tracking-[0.2em] font-medium hover:text-white transition-colors border-b border-[#ae895e] pb-1"
            >
              {authMode === 'login' ? al.switchReg : al.switchLog}
            </button>
          </div>
        </div>
      </div>
      </>
      )}
    </>
  );
};

export default Navigation;
