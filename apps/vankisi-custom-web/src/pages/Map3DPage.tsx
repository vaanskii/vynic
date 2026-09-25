import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams, useLocation } from 'react-router-dom';
import { Restaurant3DMap } from '../components/restaurant3d/Restaurant3DMap';
import { MAP_LABELS, MAP_LABELS_FLOOR2 } from '../components/restaurant3d/mapLabels';
import { SCENE_BACKGROUND } from '../components/restaurant3d/constants';
import type { FloorId } from '../components/restaurant3d/types';
import { useLanguage } from '../contexts/LanguageContext';
import { loadRes, saveRes, todayIso } from '../utils/reservationStorage';
import {
  isValidReservationDate,
  isReservationTablesFloor2Path,
  parseReservationDateFromPath,
  reservationTablesPath,
} from '../routes/reservation';

/** Space for fixed site navigation (matches Navigation.tsx bar height) */
const NAV_OFFSET = 'pt-[4.5rem] md:pt-[5rem]';

interface Map3DPageProps {
  initialFloor?: FloorId;
}

function DatePickerBar({
  date,
  minDate,
  onChange,
  label,
}: {
  date: string;
  minDate: string;
  onChange: (date: string) => void;
  label: string;
}) {
  const inputRef = useRef<HTMLInputElement>(null);

  const openPicker = useCallback(() => {
    const input = inputRef.current;
    if (!input) return;
    if (typeof input.showPicker === 'function') {
      input.showPicker();
    } else {
      input.focus();
      input.click();
    }
  }, []);

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={openPicker}
      onKeyDown={e => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          openPicker();
        }
      }}
      className="flex min-w-[9.5rem] flex-1 cursor-pointer items-center gap-3 border border-white/10 bg-[#0a0a0a] px-3 py-2 select-none sm:min-w-[11rem] sm:px-4 sm:py-2.5"
    >
      <span className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e] whitespace-nowrap">
        {label}
      </span>
      <div className="relative flex min-h-[1.25rem] min-w-0 flex-1 items-center">
        <svg
          className="pointer-events-none absolute left-0 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-white/30"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          aria-hidden
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
          />
        </svg>
        <input
          ref={inputRef}
          id="map-reservation-date"
          type="date"
          value={date}
          min={minDate}
          tabIndex={-1}
          onChange={e => {
            if (e.target.value) onChange(e.target.value);
          }}
          className="pointer-events-none w-full min-w-0 border-0 bg-transparent pl-6 pr-1 text-xs font-light text-white focus:outline-none [color-scheme:dark] sm:text-sm"
          aria-label={label}
        />
      </div>
    </div>
  );
}

function FloorToggle({
  activeFloor,
  onChange,
  labels,
}: {
  activeFloor: FloorId;
  onChange: (floor: FloorId) => void;
  labels: { floor1: string; floor2: string };
}) {
  const btnBase =
    'px-3.5 py-2 text-[10px] uppercase tracking-[0.15em] transition sm:px-4 sm:text-xs sm:tracking-[0.2em]';

  return (
    <div className="flex gap-px border border-white/10 bg-[#0a0a0a] p-1">
      <button
        type="button"
        onClick={() => onChange('floor1')}
        className={`${btnBase} ${
          activeFloor === 'floor1'
            ? 'bg-[#ae895e] font-medium text-[#050505]'
            : 'text-white/60 hover:text-[#ae895e]'
        }`}
      >
        {labels.floor1}
      </button>
      <button
        type="button"
        onClick={() => onChange('floor2')}
        className={`${btnBase} ${
          activeFloor === 'floor2'
            ? 'bg-[#ae895e] font-medium text-[#050505]'
            : 'text-white/60 hover:text-[#ae895e]'
        }`}
      >
        {labels.floor2}
      </button>
    </div>
  );
}

export default function Map3DPage({ initialFloor = 'floor1' }: Map3DPageProps) {
  const { language } = useLanguage();
  const navigate = useNavigate();
  const location = useLocation();
  const params = useParams<{ lang: string; date?: string }>();
  const currentLang = params.lang || language;
  const mapLang = (currentLang === 'ka' ? 'ka' : 'en') as 'en' | 'ka';

  const urlDate = parseReservationDateFromPath(location.pathname)
    ?? (isValidReservationDate(params.date) ? params.date : undefined);
  const isFloor2Route = isReservationTablesFloor2Path(location.pathname);

  const session = loadRes();
  const isBookingFlow = session.resStep === 2 && Boolean(urlDate);

  const [activeFloor, setActiveFloor] = useState<FloorId>(() => {
    if (isFloor2Route) return 'floor2';
    const saved = session.currentFloor;
    if (saved === 'floor1' || saved === 'floor2') return saved;
    return initialFloor;
  });

  const [selectedTables, setSelectedTables] = useState<string[]>(() => session.selectedTables || []);

  const date = urlDate || session.resDate || session.selectedDate || todayIso();

  // Booking flow requires date in URL — redirect if missing
  useEffect(() => {
    if (session.resStep !== 2) return;
    if (urlDate) return;

    const savedDate = session.resDate || session.selectedDate;
    if (savedDate && isValidReservationDate(savedDate)) {
      navigate(
        reservationTablesPath(currentLang, {
          date: savedDate,
          floor: isFloor2Route ? 'floor2' : activeFloor === 'floor2' ? 'floor2' : undefined,
        }),
        { replace: true },
      );
      return;
    }

    navigate(`/${currentLang}#reservation-section`, { replace: true });
  }, [activeFloor, currentLang, isFloor2Route, navigate, session.resDate, session.resStep, session.selectedDate, urlDate]);

  // Keep storage in sync with URL date
  useEffect(() => {
    if (!urlDate) return;
    const existing = loadRes();
    if (existing.resDate === urlDate && existing.selectedDate === urlDate) return;
    saveRes({
      ...existing,
      resDate: urlDate,
      selectedDate: urlDate,
    });
  }, [urlDate]);

  const uiLabels = useMemo(
    () =>
      mapLang === 'ka'
        ? {
            confirm: 'გაგრძელება',
            floor1: 'I სართული',
            floor2: 'II სართული',
            date: 'თარიღი',
          }
        : {
            confirm: 'Continue',
            floor1: 'Floor 1',
            floor2: 'Floor 2',
            date: 'Date',
          },
    [mapLang],
  );

  const handleDateChange = useCallback(
    (newDate: string) => {
      if (!isValidReservationDate(newDate) || newDate === date) return;

      const existing = loadRes();
      saveRes({
        ...existing,
        resDate: newDate,
        selectedDate: newDate,
      });
      setSelectedTables([]);

      navigate(
        reservationTablesPath(currentLang, {
          date: newDate,
          floor: activeFloor === 'floor2' ? 'floor2' : undefined,
        }),
        { replace: true },
      );
    },
    [activeFloor, currentLang, date, navigate],
  );

  const handleFloorChange = useCallback(
    (floor: FloorId) => {
      setActiveFloor(floor);
      const existing = loadRes();
      saveRes({ ...existing, currentFloor: floor });

      if (urlDate) {
        navigate(
          reservationTablesPath(currentLang, { date: urlDate, floor: floor === 'floor2' ? 'floor2' : undefined }),
          { replace: true },
        );
      }
    },
    [currentLang, navigate, urlDate],
  );

  const isFloor2 = activeFloor === 'floor2';

  useEffect(() => {
    document.title = isBookingFlow
      ? mapLang === 'ka'
        ? isFloor2
          ? `მაგიდის არჩევა ${date} (II) | Vankisi`
          : `მაგიდის არჩევა ${date} | Vankisi`
        : isFloor2
          ? `Choose Table ${date} (Floor 2) | Vankisi`
          : `Choose Table ${date} | Vankisi`
      : isFloor2
        ? '3D Floor 2 | Vankisi'
        : '3D Map | Vankisi';
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = '';
    };
  }, [date, isBookingFlow, isFloor2, mapLang]);

  const handleConfirm = useCallback(
    (tableIds: string[]) => {
      const existing = loadRes();
      const now = Date.now();
      saveRes({
        ...existing,
        resStep: 3,
        currentFloor: activeFloor,
        selectedTables: tableIds,
        resDate: date,
        selectedDate: date,
        resTime: existing.resTime || existing.selectedTime || '19:00',
        resGuests: existing.resGuests || '2',
        selectedTime: existing.resTime || existing.selectedTime || '19:00',
        lastActivity: now,
        timestamp: now,
      });
      navigate(`/${currentLang}#reservation-section`, { state: { preserveScroll: true } });
    },
    [activeFloor, currentLang, date, navigate],
  );

  const pageBackground = SCENE_BACKGROUND;
  const vignette =
    'radial-gradient(ellipse at center, transparent 45%, rgba(5,5,5,0.35) 100%), linear-gradient(to bottom, rgba(5,5,5,0.55) 0%, transparent 18%, transparent 78%, rgba(5,5,5,0.65) 100%)';

  return (
    <div
      className={`fixed inset-0 z-0 flex flex-col ${NAV_OFFSET}`}
      style={{ backgroundColor: pageBackground }}
    >
      <div
        className="pointer-events-none absolute inset-0 z-[1]"
        style={{ background: vignette }}
      />

      <Restaurant3DMap
        floorId={activeFloor}
        labels={isFloor2 ? MAP_LABELS_FLOOR2[mapLang] : MAP_LABELS[mapLang]}
        language={mapLang}
        date={date}
        selectedTableIds={selectedTables}
        onTableSelectionChange={setSelectedTables}
        onReserve={isBookingFlow ? handleConfirm : undefined}
        reserveButtonLabel={uiLabels.confirm}
        pollInterval={15_000}
        className="h-full min-h-0 flex-1 !rounded-none !border-0"
        topBar={
          <div className="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
            <DatePickerBar
              date={date}
              minDate={todayIso()}
              onChange={handleDateChange}
              label={uiLabels.date}
            />
            <FloorToggle
              activeFloor={activeFloor}
              onChange={handleFloorChange}
              labels={{ floor1: uiLabels.floor1, floor2: uiLabels.floor2 }}
            />
          </div>
        }
      />
    </div>
  );
}
