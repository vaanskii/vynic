abstract final class ExpenseCategory {
  static bool isSalary(Object? value) => const {
    'პერსონალი',
    'ხელფასი',
    'ხელფასები',
    'salary',
    'salaries',
  }.contains(value?.toString().trim().toLowerCase());
  static bool isProcurement(Object? value) => const {
    'market',
    'ბაზარი',
    'მარკეტი',
    'შესყიდვა',
    'შესყიდვები',
  }.contains(value?.toString().trim().toLowerCase());
}
