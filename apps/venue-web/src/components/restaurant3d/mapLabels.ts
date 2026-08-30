export type MapLanguage = 'en' | 'ka';

export interface Map3DLabels {
  statusAvailable: string;
  statusReserved: string;
  statusPending: string;
  floorLabel: string;
  tablesLabel: string;
  syncing: string;
  loadingAvailability: string;
  connectionError: string;
  loadingFloorPlan: string;
  selectedTable: string;
  selectedTables: string;
  seats: string;
  seatsTotal: string;
  seatCountUnknown: string;
  tableId: string;
  clear: string;
  close: string;
  unavailable: string;
  selectTable: string;
  deselectTable: string;
  continueBooking: string;
  pickMoreHint: string;
  doneSelecting: string;
  viewDetails: string;
  mobileTapHint: string;
  tableLabel: (id: string) => string;
}

const TABLE_LABEL_EN = (id: string) => {
  const f2 = id.match(/^f2-table(\d+)$/);
  if (f2) return `Table ${f2[1]} (Floor 2)`;
  const num = id.replace(/\D/g, '');
  return num ? `Table ${num}` : id;
};

const TABLE_LABEL_KA = (id: string) => {
  const f2 = id.match(/^f2-table(\d+)$/);
  if (f2) return `მაგიდა ${f2[1]} (II სართული)`;
  const num = id.replace(/\D/g, '');
  return num ? `მაგიდა ${num}` : id;
};

/** Short number for labels on the 3D map (e.g. "1", "4") */
export function tableDisplayNumber(id: string): string {
  const f2 = id.match(/^f2-table(\d+)$/i);
  if (f2) return f2[1];
  const num = id.replace(/\D/g, '');
  return num || id;
}

export const MAP_LABELS: Record<MapLanguage, Map3DLabels> = {
  en: {
    statusAvailable: 'Available',
    statusReserved: 'Reserved',
    statusPending: 'Pending',
    floorLabel: 'Floor 1',
    tablesLabel: 'tables',
    syncing: 'Syncing…',
    loadingAvailability: 'Loading table availability…',
    connectionError: 'Could not load table status — check server connection',
    loadingFloorPlan: 'Loading floor plan…',
    selectedTable: 'Selected table',
    selectedTables: 'Selected tables',
    seats: 'Seats',
    seatsTotal: 'seats total',
    seatCountUnknown: 'Seat count unavailable',
    tableId: 'Table ID',
    clear: 'Clear',
    close: 'Close',
    unavailable: 'Unavailable',
    selectTable: 'Select table',
    deselectTable: 'Remove selection',
    continueBooking: 'Continue',
    pickMoreHint: 'Click other tables on the map to add more',
    doneSelecting: 'Done selecting',
    viewDetails: 'Details',
    mobileTapHint: 'Tap tables on the map to select',
    tableLabel: TABLE_LABEL_EN,
  },
  ka: {
    statusAvailable: 'თავისუფალი',
    statusReserved: 'დაკავებული',
    statusPending: 'მოლოდინში',
    floorLabel: 'I სართული',
    tablesLabel: 'მაგიდა',
    syncing: 'სინქრონიზაცია…',
    loadingAvailability: 'მაგიდების ხელმისაწვდომობა იტვირთება…',
    connectionError: 'მაგიდების სტატუსის ჩატვირთვა ვერ მოხერხდა',
    loadingFloorPlan: 'სართული იტვირთება…',
    selectedTable: 'არჩეული მაგიდა',
    selectedTables: 'არჩეული მაგიდები',
    seats: 'ადგილები',
    seatsTotal: 'ადგილი სულ',
    seatCountUnknown: 'ადგილების რაოდენობა უცნობია',
    tableId: 'მაგიდის ID',
    clear: 'გასუფთავება',
    close: 'დახურვა',
    unavailable: 'მიუწვდომელი',
    selectTable: 'მაგიდის არჩევა',
    deselectTable: 'არჩევის მოხსნა',
    continueBooking: 'გაგრძელება',
    pickMoreHint: 'სხვა მაგიდების დასამატებლად დააჭირეთ რუკაზე',
    doneSelecting: 'არჩევა დასრულებულია',
    viewDetails: 'დეტალები',
    mobileTapHint: 'აირჩიეთ მაგიდები რუკაზე დაჭერით',
    tableLabel: TABLE_LABEL_KA,
  },
};

export const MAP_LABELS_FLOOR2: Record<MapLanguage, Map3DLabels> = {
  en: {
    ...MAP_LABELS.en,
    floorLabel: 'Floor 2',
    loadingFloorPlan: 'Loading floor 2 plan…',
  },
  ka: {
    ...MAP_LABELS.ka,
    floorLabel: 'II სართული',
    loadingFloorPlan: 'II სართული იტვირთება…',
  },
};

export function formatMapDate(iso: string, language: MapLanguage): string {
  if (!iso) return '';
  try {
    const d = new Date(`${iso}T12:00:00`);
    if (language === 'ka') {
      const weekdays = ['კვი', 'ორშ', 'სამ', 'ოთხ', 'ხუთ', 'პარ', 'შაბ'];
      const months = [
        'იან',
        'თებ',
        'მარ',
        'აპრ',
        'მაი',
        'ივნ',
        'ივლ',
        'აგვ',
        'სექ',
        'ოქტ',
        'ნოე',
        'დეკ',
      ];
      return `${weekdays[d.getDay()]} ${d.getDate()} ${months[d.getMonth()]}`;
    }
    return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
  } catch {
    return iso;
  }
}
