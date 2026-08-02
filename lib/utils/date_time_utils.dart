const _thaiMonths = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

/// Format booking time range with Thai date.
/// Example: "21 ก.ค. 2569  09:00 - 10:30 น."
///
/// [endTime] — explicit end DateTime (from bookingEndAt field)
/// [durationMinutes] — fallback: compute end from start + duration
/// If neither is provided, returns start-time-only format.
String formatBookingTimeRange(
  DateTime startTime, {
  DateTime? endTime,
  int? durationMinutes,
}) {
  final day = startTime.day;
  final month = _thaiMonths[startTime.month - 1];
  final year = startTime.year + 543;
  final sh = startTime.hour.toString().padLeft(2, '0');
  final sm = startTime.minute.toString().padLeft(2, '0');

  DateTime? end = endTime;
  if (end == null && durationMinutes != null && durationMinutes > 0) {
    end = startTime.add(Duration(minutes: durationMinutes));
  }

  if (end == null) return '$day $month $year  $sh:$sm น.';

  final eh = end.hour.toString().padLeft(2, '0');
  final em = end.minute.toString().padLeft(2, '0');
  return '$day $month $year  $sh:$sm - $eh:$em น.';
}
