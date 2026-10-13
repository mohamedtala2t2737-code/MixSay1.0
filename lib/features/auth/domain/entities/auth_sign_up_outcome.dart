enum AuthSignUpOutcome {
  /// A session was created immediately (email confirmation disabled).
  loggedIn,

  /// Firebase requires the email to be confirmed first.
  needsEmailConfirmation,
}
