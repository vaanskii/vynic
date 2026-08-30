export const RES_KEY = 'vankisi_reservation';

export interface ReservationData {
  resStep?: number;
  resDate?: string;
  resTime?: string;
  resGuests?: string;
  customerName?: string;
  customerPhone?: string;
  specialRequest?: string;
  selectedTables?: string[];
  selectedDate?: string;
  selectedTime?: string;
  currentFloor?: 'floor1' | 'floor2';
  createdAt?: number;
  lastActivity?: number;
  timestamp?: number;
}

export function loadRes(): ReservationData {
  try {
    return JSON.parse(localStorage.getItem(RES_KEY) || '{}');
  } catch {
    return {};
  }
}

export function saveRes(data: ReservationData & Record<string, unknown>) {
  localStorage.setItem(RES_KEY, JSON.stringify(data));
}

export function todayIso(): string {
  return new Date().toISOString().split('T')[0];
}

/** Home route only — `/:lang` or `/:lang/` */
export function isReservationHomePath(pathname: string): boolean {
  return /^\/(en|ka)\/?$/.test(pathname);
}

/** Step 2 is the table map route only; on home always show step 1 in the wizard */
export function homeWizardStep(step?: number): number {
  if (!step || step === 2) return 1;
  return step;
}

/** Drop stale step 2 when landing on home (e.g. refresh after leaving the map) */
export function clearStaleTableStepOnHome(pathname: string): void {
  if (!isReservationHomePath(pathname)) return;
  const saved = loadRes();
  if (saved.resStep === 2) {
    saveRes({ ...saved, resStep: 1 });
  }
}
