import std/times

import ./internal/time_source

type
  TimeoutConfigError* = object of ValueError

  Timeout* = object
    startedAt: Duration
    after: Duration
    timeSource: TimeSource

  Deadline* = object
    endsAt: Duration
    timeSource: TimeSource

proc initTimeout*(after: Duration; timeSource: TimeSource): Timeout =
  if after < initDuration():
    raise newException(TimeoutConfigError, "timeout duration must be non-negative")
  Timeout(startedAt: timeSource.now(), after: after, timeSource: timeSource)

proc initTimeout*(after: Duration): Timeout =
  initTimeout(after = after, timeSource = initTimeSource())

proc elapsed*(timeout: Timeout): Duration =
  timeout.timeSource.now() - timeout.startedAt

proc expired*(timeout: Timeout): bool =
  timeout.elapsed() >= timeout.after

proc remaining*(timeout: Timeout): Duration =
  let left = timeout.after - timeout.elapsed()
  if left <= initDuration(): initDuration() else: left

proc initDeadlineAt*(expiresAt: Duration; timeSource: TimeSource): Deadline =
  if expiresAt < initDuration():
    raise newException(TimeoutConfigError, "deadline time must be non-negative")
  Deadline(endsAt: expiresAt, timeSource: timeSource)

proc initDeadlineAt*(expiresAt: Duration): Deadline =
  initDeadlineAt(expiresAt = expiresAt, timeSource = initTimeSource())

proc initDeadline*(after: Duration; timeSource: TimeSource): Deadline =
  if after < initDuration():
    raise newException(TimeoutConfigError, "deadline duration must be non-negative")
  initDeadlineAt(expiresAt = timeSource.now() + after, timeSource = timeSource)

proc initDeadline*(after: Duration): Deadline =
  initDeadline(after = after, timeSource = initTimeSource())

proc expiresAt*(deadline: Deadline): Duration =
  deadline.endsAt

proc isInitialized*(deadline: Deadline): bool =
  ## Returns whether this value was created by a Deadline constructor.
  not deadline.timeSource.isNil

proc remaining*(deadline: Deadline): Duration =
  let left = deadline.endsAt - deadline.timeSource.now()
  if left <= initDuration(): initDuration() else: left

proc expired*(deadline: Deadline): bool =
  deadline.remaining() == initDuration()

proc clamp*(deadline: Deadline; requested: Duration): Duration =
  if requested < initDuration():
    raise newException(TimeoutConfigError, "requested duration must be non-negative")
  let left = deadline.remaining()
  if requested <= left: requested else: left

proc childDeadline*(deadline: Deadline; after: Duration): Deadline =
  initDeadline(after = deadline.clamp(after), timeSource = deadline.timeSource)

proc toTimeout*(deadline: Deadline): Timeout =
  initTimeout(after = deadline.remaining(), timeSource = deadline.timeSource)
