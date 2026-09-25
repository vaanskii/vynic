/** Table selection map — public URL segment */
export const RESERVATION_TABLES_SEGMENT = 'reservation/tables';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export function isValidReservationDate(date: string | undefined): date is string {
  if (!date || !ISO_DATE.test(date)) return false;
  const parsed = new Date(`${date}T12:00:00`);
  return !Number.isNaN(parsed.getTime());
}

export interface ReservationTablesPathOptions {
  date?: string;
  floor?: 'floor2';
}

export function reservationTablesPath(lang: string, options?: ReservationTablesPathOptions | 'floor2'): string {
  // Legacy: reservationTablesPath(lang, 'floor2')
  const opts: ReservationTablesPathOptions =
    options === 'floor2' ? { floor: 'floor2' } : (options ?? {});

  const { date, floor } = opts;

  if (date && isValidReservationDate(date)) {
    return floor === 'floor2'
      ? `/${lang}/${RESERVATION_TABLES_SEGMENT}/${date}/floor-2`
      : `/${lang}/${RESERVATION_TABLES_SEGMENT}/${date}`;
  }

  return floor === 'floor2'
    ? `/${lang}/${RESERVATION_TABLES_SEGMENT}/floor-2`
    : `/${lang}/${RESERVATION_TABLES_SEGMENT}`;
}

export function isReservationTablesPath(pathname: string): boolean {
  return pathname.includes(`/${RESERVATION_TABLES_SEGMENT}`);
}

/** Extract YYYY-MM-DD from reservation tables URL, if present */
export function parseReservationDateFromPath(pathname: string): string | undefined {
  const match = pathname.match(/\/reservation\/tables\/(\d{4}-\d{2}-\d{2})(?:\/|$)/);
  const date = match?.[1];
  return isValidReservationDate(date) ? date : undefined;
}

export function isReservationTablesFloor2Path(pathname: string): boolean {
  return /\/reservation\/tables\/(?:\d{4}-\d{2}-\d{2}\/)?floor-2\/?$/.test(pathname);
}
