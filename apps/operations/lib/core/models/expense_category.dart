abstract final class ExpenseCategory {
  static bool isProcurement(Object? value) => const {
    'market',
    'ბაზარი',
    'მარკეტი',
    'შესყიდვა',
    'შესყიდვები',
  }.contains(value?.toString().trim().toLowerCase());
}
