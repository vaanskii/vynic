import { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  CalendarDays,
  Settings,
  LogOut,
  Star,
  Check,
  Edit3,
  UtensilsCrossed,
} from 'lucide-react';
import { useLanguage } from '../contexts/LanguageContext';
import { useAuth } from '../contexts/AuthContext';
import { useToast } from '../contexts/ToastContext';
import { userService, authService } from '../services/api';
import Footer from '../components/Footer';
import Modal from '../components/Modal';

const LogoSVG = ({ className }: { className?: string }) => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" className={className}>
    <path fill="#ae895e" d="M133 151L151 167Q167 177 187 184L226 195L231 195L236 197L241 197L246 199L264 202L268 204L272 204L302 214Q329 226 348 248L350 251L363 269L376 301L377 308L382 321L382 325L384 328L391 354L393 357L405 396L405 401L407 408L408 434L407 435L407 445L406 446L405 457L398 478L397 477L399 466L399 439L395 419L393 416L393 413L391 410L391 407L386 395L384 385L382 383L373 353L368 342L366 333L361 322L361 319L359 317L359 314Q347 286 327 268L324 266Q309 252 288 245L267 239L256 238L250 236L245 236L239 234L233 234L208 229L192 224L170 213L167 213Q168 210 165 211L147 196L135 174Q136 167 133 165L133 151Z" />
    <path fill="#ae895e" d="M149 228L151 229Q150 232 153 231L171 245L198 256L214 259L218 261L225 261L230 263L247 265L257 268L263 268L293 277L313 288L328 303Q341 317 347 339L336 328L314 314L296 307L265 300L257 300L245 297L228 295L201 288Q178 280 163 264Q150 250 149 228Z" />
    <path fill="#ae895e" d="M176 299L198 311L218 318L238 322L245 322L272 327L278 327L297 331L317 339L332 350L332 352Q335 351 334 354L345 368L356 390L361 403L361 406L384 463L384 466L402 510L402 513L409 528L412 539L416 546L416 549L425 570L425 573Q428 574 427 571L509 367L512 356L512 350L506 339L495 334L487 334L488 329L586 329L586 334L584 334Q567 337 558 349L548 366Q545 378 539 387L537 395L516 442L516 445L514 447L507 466L505 468L505 471L500 479L498 487Q489 501 484 520L482 522L471 551L457 581L432 642L430 644L428 644L417 644L415 643Q413 645 412 643L411 638L404 623L404 620L393 595L393 592L388 582L388 579L386 577L384 568L382 566L373 543L373 540L371 538L363 515L359 508L359 505L354 495L352 487L345 472L345 469L331 436L323 413L311 386L302 373Q299 374 300 372L295 368Q296 365 294 366L283 359L264 352L235 345L229 345L216 341L201 333L186 320L184 317L176 304L176 299Z" />
  </svg>
);

interface MenuItem {
  id: string;
  quantity: number;
  price: number;
  name?: string;
}

interface Table {
  tableNumber: string;
  capacity: number;
}

interface Reservation {
  id: string;
  date: string;
  timeSlot: string;
  status: string;
  totalAmount?: number;
  menuItems: MenuItem[];
  tables: Table[];
  createdAt: string;
}

interface UserProfile {
  id: string;
  email?: string | null;
  firstName?: string | null;
  lastName?: string | null;
  phone?: string;
  role?: string;
  /** Future: set when VIP program is implemented */
  vipTier?: 'VIP' | null;
  createdAt: string;
}

type ProfileTab = 'reservations' | 'settings';

function getInitials(profile: UserProfile | null): string {
  if (!profile) return '?';
  const first = profile.firstName?.trim();
  const last = profile.lastName?.trim();
  if (first && last) return `${first[0]}${last[0]}`.toUpperCase();
  if (first) return first.slice(0, 2).toUpperCase();
  if (profile.phone) return profile.phone.replace(/\D/g, '').slice(-2) || 'U';
  return 'U';
}

function getDisplayName(profile: UserProfile | null): string {
  if (!profile) return '';
  const first = profile.firstName?.trim();
  const last = profile.lastName?.trim();
  if (first && last) return `${first} ${last}`;
  if (first) return first;
  return profile.phone || '';
}

function formatTableLabel(tableNumber: string): string {
  const match = tableNumber.match(/^table(\d{1,2})$/i);
  return match ? match[1] : tableNumber;
}

function reservationDateTime(dateStr: string, timeSlot: string): Date {
  const date = new Date(dateStr);
  const [hours, minutes] = timeSlot.split(':').map(Number);
  if (!Number.isNaN(hours)) {
    date.setHours(hours, minutes || 0, 0, 0);
  }
  return date;
}

function countGuests(reservation: Reservation): number {
  if (reservation.tables.length === 0) return 0;
  return reservation.tables.reduce((sum, t) => sum + t.capacity, 0);
}

function countDishes(menuItems: MenuItem[]): number {
  return menuItems.reduce((sum, item) => sum + item.quantity, 0);
}

const Profile = () => {
  const { t, language } = useLanguage();
  const { user, logout, refreshUser } = useAuth();
  const { showToast } = useToast();
  const navigate = useNavigate();

  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [reservations, setReservations] = useState<Reservation[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeProfileTab, setActiveProfileTab] = useState<ProfileTab>('reservations');

  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [savingProfile, setSavingProfile] = useState(false);

  const [isPasswordModalOpen, setIsPasswordModalOpen] = useState(false);
  const [passwordData, setPasswordData] = useState({
    oldPassword: '',
    newPassword: '',
    confirmNewPassword: '',
  });
  const [passwordLoading, setPasswordLoading] = useState(false);

  const locale = language === 'ka' ? 'ka-GE' : language === 'ru' ? 'ru-RU' : 'en-US';

  useEffect(() => {
    const fetchProfileData = async () => {
      if (!user) return;

      try {
        setLoading(true);
        const [profileData, reservationsData] = await Promise.all([
          userService.getProfile(),
          userService.getReservations(),
        ]);

        setProfile(profileData);
        setFirstName(profileData.firstName?.trim() || '');
        setLastName(profileData.lastName?.trim() || '');
        setReservations(reservationsData);
      } catch (err) {
        console.error('Error fetching profile data:', err);
        setError(t('profile.error'));
      } finally {
        setLoading(false);
      }
    };

    fetchProfileData();
  }, [user, t]);

  const { upcoming, past } = useMemo(() => {
    const now = new Date();
    const upcomingList: Reservation[] = [];
    const pastList: Reservation[] = [];

    for (const res of reservations) {
      const isPast =
        res.status === 'COMPLETED' ||
        reservationDateTime(res.date, res.timeSlot) < now;

      if (isPast) {
        pastList.push(res);
      } else {
        upcomingList.push(res);
      }
    }

    return { upcoming: upcomingList, past: pastList };
  }, [reservations]);

  const handleLogout = async () => {
    await logout();
    navigate(`/${language}`);
  };

  const handleSaveProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    setSavingProfile(true);
    try {
      const updated = await userService.updateProfile({
        firstName: firstName.trim(),
        lastName: lastName.trim(),
      });
      setProfile((prev) => (prev ? { ...prev, ...updated } : prev));
      await refreshUser();
      showToast(t('profile.profileUpdated'), 'success');
    } catch {
      showToast(t('profile.error'), 'error');
    } finally {
      setSavingProfile(false);
    }
  };

  const handlePasswordChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setPasswordData({ ...passwordData, [e.target.name]: e.target.value });
  };

  const submitPasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordLoading(true);

    if (passwordData.newPassword !== passwordData.confirmNewPassword) {
      showToast(t('profile.passwordMismatch'), 'error');
      setPasswordLoading(false);
      return;
    }

    try {
      await authService.changePassword({
        oldPassword: passwordData.oldPassword,
        newPassword: passwordData.newPassword,
      });
      showToast(t('profile.passwordUpdated'), 'success');
      setPasswordData({ oldPassword: '', newPassword: '', confirmNewPassword: '' });
      setIsPasswordModalOpen(false);
    } catch (err: unknown) {
      const message = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      showToast(message || t('profile.error'), 'error');
    } finally {
      setPasswordLoading(false);
    }
  };

  const formatDate = (dateString: string) =>
    new Date(dateString).toLocaleDateString(locale, {
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });

  const displayName = getDisplayName(profile);
  const greeting = displayName
    ? `${t('profile.greeting')}, ${displayName}`
    : t('profile.greeting');
  const isVip = profile?.vipTier === 'VIP';
  const tierLabel = isVip ? t('profile.tierVip') : t('profile.tierGuest');

  if (loading) {
    return (
      <div className="min-h-screen bg-[#050505] flex items-center justify-center pt-32">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#ae895e] mx-auto" />
          <p className="mt-4 text-[#ae895e] font-light tracking-widest text-xs uppercase">
            {t('profile.loading')}
          </p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-[#050505] flex items-center justify-center pt-32">
        <p className="text-red-400 font-light">{error}</p>
      </div>
    );
  }

  return (
    <>
      <div className="animate-fade-up-init pt-32 pb-32 min-h-screen bg-[#050505] relative">
        <div className="max-w-7xl mx-auto px-6 md:px-8">
          <div className="mb-16 border-b border-white/5 pb-8 flex items-end justify-between">
            <div>
              <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-medium block mb-4">
                {t('profile.title')}
              </span>
              <h1 className="text-4xl md:text-5xl font-light tracking-wide text-white/95">
                {greeting}
              </h1>
            </div>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-16 items-start">
            {/* Sidebar */}
            <div className="lg:col-span-4 space-y-8">
              <div className="bg-[#0a0a0a] border border-white/5 p-8 relative overflow-hidden shadow-2xl flex flex-col items-center text-center">
                <div className="w-24 h-24 rounded-full border border-[#ae895e] p-1 mb-6 relative">
                  <div className="w-full h-full bg-[#ae895e]/10 rounded-full flex items-center justify-center text-2xl text-[#ae895e] font-light">
                    {getInitials(profile)}
                  </div>
                  <div
                    className={`absolute -bottom-2 left-1/2 -translate-x-1/2 text-[8px] uppercase tracking-widest px-3 py-1 font-bold rounded-sm whitespace-nowrap flex items-center gap-1 ${
                      isVip
                        ? 'bg-[#ae895e] text-black'
                        : 'bg-white/10 text-white/50 border border-white/10'
                    }`}
                  >
                    {isVip && <Star size={8} className="fill-black" />}
                    {tierLabel}
                  </div>
                </div>

                <h3 className="text-xl font-light text-white/90 mb-1">
                  {displayName || t('profile.title')}
                </h3>
                {profile?.email && (
                  <p className="text-white/40 text-xs font-light mb-8">{profile.email}</p>
                )}

                <div className="w-full flex flex-col gap-2">
                  <button
                    type="button"
                    onClick={() => setActiveProfileTab('reservations')}
                    className={`flex items-center gap-4 px-6 py-4 text-xs tracking-widest uppercase transition-all duration-300 ${
                      activeProfileTab === 'reservations'
                        ? 'bg-[#ae895e]/10 text-[#ae895e] border-l-2 border-[#ae895e]'
                        : 'text-white/50 hover:text-white hover:bg-white/5 border-l-2 border-transparent'
                    }`}
                  >
                    <CalendarDays size={16} /> {t('profile.tabRes')}
                  </button>
                  <button
                    type="button"
                    onClick={() => setActiveProfileTab('settings')}
                    className={`flex items-center gap-4 px-6 py-4 text-xs tracking-widest uppercase transition-all duration-300 ${
                      activeProfileTab === 'settings'
                        ? 'bg-[#ae895e]/10 text-[#ae895e] border-l-2 border-[#ae895e]'
                        : 'text-white/50 hover:text-white hover:bg-white/5 border-l-2 border-transparent'
                    }`}
                  >
                    <Settings size={16} /> {t('profile.tabSettings')}
                  </button>
                  <button
                    type="button"
                    onClick={handleLogout}
                    className="flex items-center gap-4 px-6 py-4 text-xs tracking-widest uppercase text-white/30 hover:text-red-400 hover:bg-red-400/5 border-l-2 border-transparent transition-all duration-300 mt-4 border-t border-white/5"
                  >
                    <LogOut size={16} /> {t('profile.tabLogout')}
                  </button>
                </div>
              </div>
            </div>

            {/* Content */}
            <div className="lg:col-span-8">
              {activeProfileTab === 'reservations' && (
                <div className="space-y-12 animate-fade-up-init">
                  <div>
                    <h4 className="text-[#ae895e] uppercase tracking-[0.3em] text-xs font-medium mb-6 flex items-center gap-3">
                      <span className="w-2 h-2 rounded-full bg-[#ae895e] animate-pulse" />
                      {t('profile.upcoming')}
                    </h4>

                    {upcoming.length === 0 ? (
                      <p className="text-white/30 font-light text-sm">{t('profile.noUpcoming')}</p>
                    ) : (
                      <div className="space-y-6">
                        {upcoming.map((reservation) => {
                          const dishCount = countDishes(reservation.menuItems);
                          const tableLabel = reservation.tables
                            .map((t) => formatTableLabel(t.tableNumber))
                            .join(', ');

                          return (
                            <div
                              key={reservation.id}
                              className="bg-gradient-to-br from-[#0a0a0a] to-[#050505] border border-[#ae895e]/30 shadow-[0_10px_40px_rgba(174,137,94,0.05)] p-8 md:p-10 relative overflow-hidden group"
                            >
                              <div className="absolute top-0 right-0 p-6 opacity-5 pointer-events-none">
                                <LogoSVG className="w-48 h-48" />
                              </div>

                              <div className="flex justify-between items-start mb-8 border-b border-white/10 pb-6 relative z-10">
                                <div>
                                  <span className="text-white/40 text-[10px] uppercase tracking-widest block mb-2">
                                    ID: {reservation.id.slice(0, 8)}
                                  </span>
                                  <div className="flex items-center gap-2 text-[#ae895e] bg-[#ae895e]/10 px-3 py-1.5 rounded-sm border border-[#ae895e]/20 w-max">
                                    <Check size={14} />
                                    <span className="text-[10px] uppercase tracking-widest font-bold">
                                      {t('profile.confirmed')}
                                    </span>
                                  </div>
                                </div>
                              </div>

                              <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-8 relative z-10">
                                <div>
                                  <span className="text-white/30 text-[10px] uppercase tracking-[0.2em] block mb-2">
                                    {t('profile.resDate')}
                                  </span>
                                  <span className="text-white/90 font-light text-lg">
                                    {formatDate(reservation.date)}
                                  </span>
                                </div>
                                <div>
                                  <span className="text-white/30 text-[10px] uppercase tracking-[0.2em] block mb-2">
                                    {t('profile.resTime')}
                                  </span>
                                  <span className="text-white/90 font-light text-lg">
                                    {reservation.timeSlot}
                                  </span>
                                </div>
                                <div>
                                  <span className="text-white/30 text-[10px] uppercase tracking-[0.2em] block mb-2">
                                    {t('profile.resTable')}
                                  </span>
                                  <span className="text-[#ae895e] font-medium text-lg">
                                    {tableLabel || '—'}
                                  </span>
                                </div>
                                <div>
                                  <span className="text-white/30 text-[10px] uppercase tracking-[0.2em] block mb-2">
                                    {t('profile.resGuests')}
                                  </span>
                                  <span className="text-white/90 font-light text-lg">
                                    {countGuests(reservation) || '—'}
                                  </span>
                                </div>
                              </div>

                              {dishCount > 0 && (
                                <div className="border-t border-white/5 pt-6 flex justify-between items-center relative z-10">
                                  <div className="flex items-center gap-3">
                                    <UtensilsCrossed size={16} className="text-white/40" />
                                    <span className="text-sm font-light text-white/60">
                                      {t('profile.preOrder')}: {dishCount} {t('profile.dishes')}
                                    </span>
                                  </div>
                                </div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>

                  <div>
                    <h4 className="text-white/40 uppercase tracking-[0.3em] text-xs font-medium mb-6">
                      {t('profile.past')}
                    </h4>

                    {past.length === 0 ? (
                      <p className="text-white/20 font-light text-sm">{t('profile.noReservations')}</p>
                    ) : (
                      <div className="space-y-4">
                        {past.map((reservation) => (
                          <div
                            key={reservation.id}
                            className="bg-[#0a0a0a] border border-white/5 p-6 flex flex-col md:flex-row justify-between items-start md:items-center gap-6"
                          >
                            <div className="flex flex-col gap-2">
                              <span className="text-white/30 text-[10px] uppercase tracking-widest">
                                {reservation.id.slice(0, 8)}
                              </span>
                              <span className="text-white/80 font-light">
                                {formatDate(reservation.date)} • {reservation.timeSlot}
                              </span>
                            </div>
                            <div className="flex items-center gap-6 w-full md:w-auto justify-between md:justify-end">
                              <span className="text-white/40 text-sm font-light">
                                {countGuests(reservation)} {t('profile.resGuests')}
                              </span>
                              <span className="text-white/30 text-[10px] uppercase tracking-widest border border-white/10 px-2 py-1 rounded-sm">
                                {t('profile.completed')}
                              </span>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              )}

              {activeProfileTab === 'settings' && (
                <form
                  onSubmit={handleSaveProfile}
                  className="bg-[#0a0a0a] border border-white/5 p-8 md:p-12 animate-fade-up-init shadow-2xl relative"
                >
                  <h4 className="text-[#ae895e] uppercase tracking-[0.3em] text-xs font-medium mb-10 pb-4 border-b border-white/5 flex items-center justify-between">
                    <span>{t('profile.personalInfo')}</span>
                    <Edit3 size={16} className="text-white/30" />
                  </h4>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-8 mb-12">
                    <div className="space-y-3">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-white/40">
                        {t('auth.firstName')}
                      </label>
                      <input
                        type="text"
                        value={firstName}
                        onChange={(e) => setFirstName(e.target.value)}
                        className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors"
                      />
                    </div>
                    <div className="space-y-3">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-white/40">
                        {t('auth.lastName')}
                      </label>
                      <input
                        type="text"
                        value={lastName}
                        onChange={(e) => setLastName(e.target.value)}
                        className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors"
                      />
                    </div>
                    <div className="space-y-3">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-white/40">
                        {t('auth.phone')}
                      </label>
                      <input
                        type="tel"
                        value={profile?.phone || ''}
                        disabled
                        className="w-full bg-transparent border-b border-white/10 pb-3 text-white/40 font-light outline-none cursor-not-allowed"
                      />
                    </div>
                    <div className="space-y-3 md:col-span-2">
                      <label className="text-[10px] uppercase tracking-[0.2em] text-white/40">
                        {t('profile.email')}
                      </label>
                      <input
                        type="email"
                        value={profile?.email || ''}
                        disabled
                        className="w-full bg-transparent border-b border-white/10 pb-3 text-white/40 font-light outline-none cursor-not-allowed"
                      />
                      <span className="text-[10px] text-white/20 mt-1 block">
                        {t('profile.emailChangeNote')}
                      </span>
                    </div>
                  </div>

                  <div className="flex flex-col sm:flex-row gap-4">
                    <button
                      type="submit"
                      disabled={savingProfile}
                      className="bg-[#ae895e] text-black px-8 py-4 uppercase tracking-[0.2em] text-xs font-bold hover:bg-white transition-colors flex items-center justify-center gap-3 rounded-sm disabled:opacity-50"
                    >
                      {savingProfile ? t('profile.loading') : t('profile.saveBtn')}{' '}
                      <Check size={16} />
                    </button>
                    <button
                      type="button"
                      onClick={() => setIsPasswordModalOpen(true)}
                      className="border border-white/10 text-white/60 hover:text-white hover:border-[#ae895e]/50 px-8 py-4 uppercase tracking-[0.2em] text-xs transition-colors rounded-sm"
                    >
                      {t('profile.changePassword')}
                    </button>
                  </div>
                </form>
              )}
            </div>
          </div>
        </div>
      </div>

      <Modal
        isOpen={isPasswordModalOpen}
        onClose={() => setIsPasswordModalOpen(false)}
        title={t('profile.changePassword')}
      >
        <form onSubmit={submitPasswordChange} className="space-y-4">
          <div>
            <label className="block text-[10px] uppercase tracking-[0.2em] text-white/40 mb-2">
              {t('profile.currentPassword')}
            </label>
            <input
              type="password"
              name="oldPassword"
              value={passwordData.oldPassword}
              onChange={handlePasswordChange}
              required
              className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors"
            />
          </div>
          <div>
            <label className="block text-[10px] uppercase tracking-[0.2em] text-white/40 mb-2">
              {t('profile.newPassword')}
            </label>
            <input
              type="password"
              name="newPassword"
              value={passwordData.newPassword}
              onChange={handlePasswordChange}
              required
              minLength={6}
              className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors"
            />
          </div>
          <div>
            <label className="block text-[10px] uppercase tracking-[0.2em] text-white/40 mb-2">
              {t('profile.confirmNewPassword')}
            </label>
            <input
              type="password"
              name="confirmNewPassword"
              value={passwordData.confirmNewPassword}
              onChange={handlePasswordChange}
              required
              minLength={6}
              className="w-full bg-transparent border-b border-white/20 pb-3 text-white font-light focus:border-[#ae895e] outline-none transition-colors"
            />
          </div>
          <div className="flex justify-end gap-4 pt-4">
            <button
              type="button"
              onClick={() => setIsPasswordModalOpen(false)}
              className="text-white/40 hover:text-white text-xs uppercase tracking-widest transition-colors"
            >
              {t('profile.cancel')}
            </button>
            <button
              type="submit"
              disabled={passwordLoading}
              className="bg-[#ae895e] text-black px-6 py-3 uppercase tracking-[0.2em] text-xs font-bold hover:bg-white transition-colors disabled:opacity-50"
            >
              {passwordLoading ? t('profile.loading') : t('profile.updatePassword')}
            </button>
          </div>
        </form>
      </Modal>

      <Footer />
    </>
  );
};

export default Profile;
