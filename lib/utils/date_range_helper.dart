class DateRangeHelper {
  /// Returns the first millisecond of the given month.
  static DateTime startOfMonth(DateTime month) {
    return DateTime(month.year, month.month, 1);
  }

  /// Returns the last millisecond of the given month (23:59:59.999).
  static DateTime endOfMonth(DateTime month) {
    final firstOfNextMonth = DateTime(month.year, month.month + 1, 1);
    return firstOfNextMonth.subtract(const Duration(milliseconds: 1));
  }

  /// Returns true if [date] falls within the same year/month as [month].
  static bool isInMonth(DateTime date, DateTime month) {
    return date.year == month.year && date.month == month.month;
  }
}