const Duration bnbuCampusUtcOffset = Duration(hours: 8);

/// Returns BNBU campus wall-clock fields for an absolute instant.
///
/// The returned value is only a calendar representation. Its local time-zone
/// flag must not be used to recover the original instant.
DateTime toBnbuCampusClock(DateTime instant) {
  final shifted = instant.toUtc().add(bnbuCampusUtcOffset);
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

/// Converts BNBU campus wall-clock fields into their absolute UTC instant.
DateTime bnbuCampusClockToUtc(DateTime campusClock) {
  return DateTime.utc(
    campusClock.year,
    campusClock.month,
    campusClock.day,
    campusClock.hour,
    campusClock.minute,
    campusClock.second,
    campusClock.millisecond,
    campusClock.microsecond,
  ).subtract(bnbuCampusUtcOffset);
}
