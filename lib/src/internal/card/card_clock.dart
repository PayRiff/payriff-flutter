import 'package:flutter/foundation.dart';

/// Time for the card flow: the 429 backoff, the `/pay` retry, the
/// `/three-ds` loop and status polling.
abstract interface class CardClock {
  /// The current time.
  DateTime now();

  /// Completes after [duration].
  Future<void> sleep(Duration duration);
}

/// The wall clock.
final class SystemCardClock implements CardClock {
  /// Creates the wall clock.
  const SystemCardClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);
}

/// Replaces the card flow's clock, so tests can run its schedule on fake
/// time. For tests only.
@visibleForTesting
CardClock? debugPayriffCardClock;

/// The clock new card payments use.
CardClock get cardClock => debugPayriffCardClock ?? const SystemCardClock();
