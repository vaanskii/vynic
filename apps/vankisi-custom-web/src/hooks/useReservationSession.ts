import { useEffect, useCallback, useRef } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';
import { isReservationTablesPath } from '../routes/reservation';

// ─── Types ────────────────────────────────────────────────────────────────────
export interface ReservationSession {
  // Existing reservation data
  resStep?: number;
  resDate?: string;
  resTime?: string;
  resGuests?: string;
  customerName?: string;
  customerPhone?: string;
  specialRequest?: string;
  selectedTables?: string[];

  // Session metadata
  createdAt: number;
  lastActivity: number;
}

// ─── Constants ────────────────────────────────────────────────────────────────
const RES_KEY = 'vankisi_reservation';
const PREORDER_KEY = 'vankisi_preorder';
const EXPIRATION_TIME = 1 * 60 * 1000; // 20 minutes in milliseconds
const CHECK_INTERVAL = 60 * 1000; // 1 minute in milliseconds

// ─── Helper: Get Current Session ──────────────────────────────────────────────
const getSession = (): ReservationSession | null => {
  try {
    const data = localStorage.getItem(RES_KEY);
    return data ? JSON.parse(data) : null;
  } catch {
    return null;
  }
};

// ─── Helper: Clear Session ────────────────────────────────────────────────────
const clearSession = () => {
  localStorage.removeItem(RES_KEY);
  localStorage.removeItem(PREORDER_KEY);
};

export const useReservationSession = () => {
  const { language } = useLanguage();
  const navigate = useNavigate();
  const location = useLocation();
  const checkIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Function to expire the session
  const expireSession = useCallback(() => {
    const session = getSession();
    if (session) {
      clearSession();
      // Optionally redirect to home if they were in a reservation process
      // This is a safety check to avoid infinite loops if already on home
      if (
        location.pathname.includes('/checkout') ||
        (session.resStep && session.resStep > 1 && !isReservationTablesPath(location.pathname))
      ) {
        navigate(`/${language}`, { replace: true });
        window.location.reload(); // Force a fresh state
      }
    }
  }, [language, navigate, location.pathname]);

  // Function to check expiration
  const checkExpiration = useCallback(() => {
    const session = getSession();
    if (!session) return;

    const now = Date.now();
    if (now - session.lastActivity > EXPIRATION_TIME) {
      expireSession();
    }
  }, [expireSession]);

  // Function to update last activity
  const updateActivity = useCallback(() => {
    const session = getSession();
    if (!session) return;

    const now = Date.now();
    // Only update if at least 5 seconds passed to reduce disk I/O
    if (now - session.lastActivity > 5000) {
      const updatedSession: ReservationSession = {
        ...session,
        lastActivity: now
      };
      localStorage.setItem(RES_KEY, JSON.stringify(updatedSession));
    }
  }, []);

  useEffect(() => {
    // 1. Initial check on load
    checkExpiration();

    // 2. Activity listeners
    const activityEvents = ['mousemove', 'keydown', 'click', 'scroll', 'visibilitychange'];

    activityEvents.forEach(event => {
      window.addEventListener(event, updateActivity);
    });

    // 3. Background interval check
    checkIntervalRef.current = setInterval(checkExpiration, CHECK_INTERVAL);

    // 4. Multi-tab sync
    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === RES_KEY) {
        if (e.newValue === null) {
          // Session was cleared in another tab
          window.location.reload();
        } else {
          // Session was updated in another tab, check if it's expired
          checkExpiration();
        }
      }
    };
    window.addEventListener('storage', handleStorageChange);

    // Cleanup
    return () => {
      activityEvents.forEach(event => {
        window.removeEventListener(event, updateActivity);
      });
      if (checkIntervalRef.current) {
        clearInterval(checkIntervalRef.current);
      }
      window.removeEventListener('storage', handleStorageChange);
    };
  }, [checkExpiration, updateActivity]);

  // 5. Route change check
  useEffect(() => {
    checkExpiration();
  }, [location.pathname, checkExpiration]);

  return {
    session: getSession(),
    clearSession,
    updateActivity
  };
};
