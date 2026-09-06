/** Legacy procurement categories have no independent Expense meaning. */
export const isProcurementCategory = (value: unknown): boolean =>
  ['market', 'ბაზარი', 'მარკეტი', 'შესყიდვა', 'შესყიდვები'].includes(
    String(value ?? '')
      .trim()
      .toLowerCase(),
  );
export const isSalaryCategory = (value: unknown): boolean =>
  ['პერსონალი', 'ხელფასი', 'ხელფასები', 'salary', 'salaries'].includes(
    String(value ?? '')
      .trim()
      .toLowerCase(),
  );
