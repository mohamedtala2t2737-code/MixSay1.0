/// The only age fact this app ever puts in a public document.
///
/// The exact birth date stays in `users/{uid}`, which is readable only by its
/// owner; `publicProfiles` carries this group so the server can refuse to
/// return someone from another group. Firestore recomputes the same value from
/// the private date, so both sides use UTC calendar parts and ignore the
/// time of day: the boundary day is the birthday itself, and a 29 February
/// birthday matures on 1 March in a year with no 29 February. That is the
/// convention [isAtLeastThirteen] already applies at sign-up.
enum AgeGroup {
  teen('teen'),
  adult('adult');

  const AgeGroup(this.wire);

  /// The value stored in `ageGroup`.
  final String wire;

  static AgeGroup? fromWire(Object? value) => switch (value) {
    'teen' => teen,
    'adult' => adult,
    _ => null,
  };

  /// The group [birthDate] places someone in at [now].
  ///
  /// Anyone under the teen floor lands in [teen] rather than [adult]: a
  /// malformed or underage date must never widen an adult's reach.
  static AgeGroup of({required DateTime birthDate, required DateTime now}) {
    final birthday = DateTime.utc(
      birthDate.year,
      birthDate.month,
      birthDate.day,
    );
    final adulthood = DateTime.utc(
      birthday.year + 18,
      birthday.month,
      birthday.day,
    );
    return !now.toUtc().isBefore(adulthood) ? adult : teen;
  }
}
