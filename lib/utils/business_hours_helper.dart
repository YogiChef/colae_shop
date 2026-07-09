/// Canonical helper for reading service_shops.businessHours from Firestore.
///
/// Vendor saves: { 'open': '09:00', 'close': '21:00', 'closed': false }
/// ⚠️ DO NOT access businessHours fields directly — use parseBusinessDay().
class DayStatus {
  final bool isOpen;
  final String? openTime;
  final String? closeTime;

  const DayStatus({
    required this.isOpen,
    this.openTime,
    this.closeTime,
  });
}

DayStatus parseBusinessDay(Map<String, dynamic>? dayData) {
  if (dayData == null) return const DayStatus(isOpen: false);

  // canonical field: 'closed' (NOT 'isOpen')
  final closed = dayData['closed'] as bool? ?? true;

  return DayStatus(
    isOpen: !closed,
    openTime: dayData['open'] as String?,   // canonical: 'open' (NOT 'openTime')
    closeTime: dayData['close'] as String?, // canonical: 'close' (NOT 'closeTime')
  );
}

const dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

String dayLabelThai(String key) {
  const map = {
    'mon': 'จันทร์',
    'tue': 'อังคาร',
    'wed': 'พุธ',
    'thu': 'พฤหัสบดี',
    'fri': 'ศุกร์',
    'sat': 'เสาร์',
    'sun': 'อาทิตย์',
  };
  return map[key] ?? key;
}
