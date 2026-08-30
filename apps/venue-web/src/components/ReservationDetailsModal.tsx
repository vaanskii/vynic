import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { useLanguage } from '../contexts/LanguageContext';
import { useTr } from '../hooks/useTr';
import { loadRes, todayIso } from '../utils/reservationStorage';

interface ReservationDetailsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (details: { date: string; time: string; guests: string }) => void;
  selectedTableCount: number;
}

const TIME_SLOTS = ['10:00', '11:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00', '20:00', '21:00', '22:00'];

export default function ReservationDetailsModal({
  isOpen,
  onClose,
  onSubmit,
  selectedTableCount,
}: ReservationDetailsModalProps) {
  const { language } = useLanguage();
  const tr = useTr();
  const saved = loadRes();

  const [date, setDate] = useState(saved.resDate || saved.selectedDate || todayIso());
  const [time, setTime] = useState(saved.resTime || saved.selectedTime || '19:00');
  const [guests, setGuests] = useState(saved.resGuests || '2');

  useEffect(() => {
    if (!isOpen) return;
    const s = loadRes();
    setDate(s.resDate || s.selectedDate || todayIso());
    setTime(s.resTime || s.selectedTime || '19:00');
    setGuests(s.resGuests || '2');
  }, [isOpen]);

  useEffect(() => {
    if (!isOpen) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const steps = [
    { step: 1, title: tr('Table Selection', 'მაგიდის შერჩევა', 'Выбор столика'), done: true },
    { step: 2, title: tr('Date & Time', 'თარიღი და დრო', 'Дата и время'), done: false, active: true },
    { step: 3, title: tr('Pre-order', 'პრე-მენიუ', 'Предзаказ'), done: false },
    { step: 4, title: tr('Confirmation', 'დადასტურება', 'Подтверждение'), done: false },
  ];

  return createPortal(
    <div className="fixed inset-0 z-[100] flex items-center justify-center p-4 sm:p-6">
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" onClick={onClose} aria-hidden />

      <div
        role="dialog"
        aria-modal="true"
        className="relative w-full max-w-5xl max-h-[92dvh] overflow-y-auto custom-scrollbar bg-[#0a0a0a] border border-white/10 shadow-2xl animate-fade-up-init"
      >
        <button
          type="button"
          onClick={onClose}
          className="absolute right-4 top-4 z-10 text-white/40 hover:text-white transition-colors cursor-pointer"
          aria-label={tr('Close', 'დახურვა', 'Закрыть')}
        >
          <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <div className="grid grid-cols-1 md:grid-cols-12 gap-0 md:gap-8 p-6 sm:p-8 md:p-10">
          {/* Sidebar */}
          <div className="md:col-span-5 pb-6 md:pb-0 md:border-r md:border-white/5 md:pr-8">
            <span className="text-[#ae895e] uppercase tracking-[0.4em] text-xs font-medium block mb-4">
              {tr('Personal Journey', 'პერსონალური მოგზაურობა', 'Личное путешествие')}
            </span>
            <h3 className="text-2xl sm:text-3xl font-light mb-4 leading-[1.3] text-white/95">
              {language === 'ka' ? (
                <>დაგეგმეთ თქვენი <span className="italic font-serif text-[#ae895e]">განსაკუთრებული</span> საღამო</>
              ) : language === 'ru' ? (
                <>Спланируйте свой <span className="italic font-serif text-[#ae895e]">незабываемый</span> вечер</>
              ) : (
                <>Plan your <span className="italic font-serif text-[#ae895e]">unforgettable</span> evening</>
              )}
            </h3>
            <p className="text-white/50 text-sm sm:text-base mb-8 leading-relaxed font-light">
              {tr(
                'Our reservation system lets you pre-define every detail of your evening — from choosing the ideal table to an exclusive wine tasting.',
                'ჩვენი ინტუიციური დაჯავშნის სისტემა გაძლევთ პრივილეგიას, წინასწარ განსაზღვროთ საღამოს ყოველი დეტალი — იდეალური მაგიდის შერჩევიდან, ექსკლუზიური ღვინის დეგუსტაციამდე.',
                'Наша система бронирования позволяет заранее продумать каждую деталь вечера — от выбора идеального столика до эксклюзивной винной дегустации.',
              )}
            </p>

            <div className="space-y-5 border-l border-white/10 pl-5 relative">
              <div
                className="absolute left-[-1px] top-0 w-[1px] bg-[#ae895e] transition-all duration-700"
                style={{ height: '50%' }}
              />
              {steps.map(s => (
                <div
                  key={s.step}
                  className={`transition-opacity duration-300 ${
                    s.done || s.active ? 'opacity-100' : 'opacity-30'
                  }`}
                >
                  <h5 className={`text-xs font-medium tracking-widest uppercase mb-0.5 ${
                    s.active ? 'text-[#ae895e]' : s.done ? 'text-white/70' : 'text-white'
                  }`}>
                    {tr(`Step 0${s.step}`, `ნაბიჯი 0${s.step}`, `Шаг 0${s.step}`)}
                  </h5>
                  <p className="text-xs font-light text-white/50">{s.title}</p>
                </div>
              ))}
            </div>
          </div>

          {/* Form */}
          <div className="md:col-span-7 flex flex-col min-h-[280px]">
            <div className="flex justify-between items-center mb-6 pb-4 border-b border-white/5">
              <h4 className="text-lg sm:text-xl font-light tracking-wide text-white/90">
                {tr('Enter Details', 'მიუთითეთ დეტალები', 'Укажите детали')}
              </h4>
              {selectedTableCount > 0 && (
                <span className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]/80">
                  {tr(
                    `${selectedTableCount} table(s) selected`,
                    `${selectedTableCount} მაგიდა`,
                    `${selectedTableCount} стол(ов)`,
                  )}
                </span>
              )}
            </div>

            <div className="flex-grow space-y-6 sm:space-y-8">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                <div className="space-y-2">
                  <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                    {tr('Date', 'თარიღი', 'Дата')}
                  </label>
                  <div className="relative">
                    <svg className="absolute left-4 top-1/2 -translate-y-1/2 text-white/30 w-4 h-4 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                    <input
                      type="date"
                      value={date}
                      min={todayIso()}
                      onChange={e => setDate(e.target.value)}
                      className="w-full bg-[#050505] border border-white/10 p-4 pl-12 text-white font-light focus:border-[#ae895e] outline-none transition-colors"
                    />
                  </div>
                </div>
                <div className="space-y-2">
                  <label className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e]">
                    {tr('Time', 'დრო', 'Время')}
                  </label>
                  <div className="relative">
                    <svg className="absolute left-4 top-1/2 -translate-y-1/2 text-white/30 w-4 h-4 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <select
                      value={time}
                      onChange={e => setTime(e.target.value)}
                      className="w-full bg-[#050505] border border-white/10 p-4 pl-12 text-white font-light focus:border-[#ae895e] outline-none transition-colors appearance-none"
                    >
                      {TIME_SLOTS.map(t => (
                        <option key={t} value={t}>{t}</option>
                      ))}
                    </select>
                  </div>
                </div>
              </div>

              <div className="space-y-2">
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
                    value={guests}
                    onChange={e => setGuests(e.target.value)}
                    placeholder="2"
                    className="w-full bg-[#050505] border border-white/10 p-4 pl-12 text-white font-light focus:border-[#ae895e] outline-none transition-colors placeholder:text-white/25 [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                  />
                </div>
              </div>
            </div>

            <div className="mt-8 pt-6 border-t border-white/5">
              <button
                type="button"
                disabled={!date}
                onClick={() => onSubmit({ date, time, guests: guests || '2' })}
                className={`w-full py-4 uppercase tracking-[0.2em] text-xs font-semibold flex items-center justify-center gap-3 transition-all duration-300 cursor-pointer ${
                  !date
                    ? 'bg-white/5 text-white/20 cursor-not-allowed'
                    : 'bg-[#ae895e] text-[#050505] hover:bg-white'
                }`}
              >
                {tr('Continue', 'გაგრძელება', 'Продолжить')}
                <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17 8l4 4m0 0l-4 4m4-4H3" />
                </svg>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  );
}
