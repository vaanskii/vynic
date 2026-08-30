export const WEBSITE_TABLE_MAPPINGS = [
  ...Array.from({ length: 10 }, (_, i) => ({
    websiteTableNumber: `table${i + 1}`,
    posTableNumber: String(i + 1),
    posFloor: 'first',
    capacity: i < 4 ? 2 : i < 8 ? 4 : 6,
  })),
  {
    websiteTableNumber: 'f2-table1',
    posTableNumber: '1',
    posFloor: 'second',
    capacity: 4,
  },
  {
    websiteTableNumber: 'f2-table2',
    posTableNumber: '2',
    posFloor: 'second',
    capacity: 4,
  },
  {
    websiteTableNumber: 'f2-table3',
    posTableNumber: '3',
    posFloor: 'second',
    capacity: 6,
  },
  {
    websiteTableNumber: 'f2-table4',
    posTableNumber: '4',
    posFloor: 'second',
    capacity: 6,
  },
] as const;
