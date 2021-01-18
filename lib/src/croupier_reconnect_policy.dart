part of croupier;

/// The Reconnect Policy intended for use by a [ClientSocket] to determine what
/// to do if a connection to the socket server fails.
///
/// If [autoReconnect] is true, the delay before reconnecting is calculated
/// iteratively based on the number of attempts that have already been made to
/// reconnect since the connection has been lost.
///
/// The following formula is used to work out the timeout before re-connecting:
/// ```
/// timeout = round(
///   round(initialDelay + (randomness * random())) * (multiplier ^ attempts)
/// )
/// ```
/// where attempts is the number of attempts.
///
/// If timeout > maxDelay, timeout will simply be set to maxDelay.
class ReconnectPolicy {
  /// Whether or not to automatically reconnect the socket when it loses the
  /// connection to the server.
  /// Default is true.
  final bool autoReconnect;

  /// The minimum delay to wait before attempting to reconnect to the socket
  /// server in milliseconds.
  /// Default is 10000 (10s)
  final int initialDelay;

  /// The upper-bound of the random number of milliseconds to add to
  /// [initialDelay] when computing the amount of time to reconnect to the
  /// socket server.
  ///
  /// Default is 10000 (10s).
  final int randomness;

  /// The base that the number of attempts (exponent) is raised to when
  /// multiplying by the initial timeout based on [initialDelay] and
  /// [randomness].
  ///
  /// Defaults to 1.5.
  final double multiplier;

  /// The maximum delay to wait before reconnecting. If the calculated delay
  /// is greater than this value, this value will simply be used instead.
  ///
  /// Defaults to 60000 (60s).
  final int maxDelay;

  const ReconnectPolicy({
    this.autoReconnect = true,
    this.initialDelay = 10000,
    this.randomness = 10000,
    this.multiplier = 1.5,
    this.maxDelay = 60000,
  });
}
