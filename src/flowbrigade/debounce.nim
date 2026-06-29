import std/times

import ./internal/time_source

type
  DebounceConfigError* = object of ValueError

  Debouncer* = object
    delay: Duration
    pending: bool
    lastCall: Duration
    timeSource: TimeSource

proc initDebouncer*(delay: Duration; timeSource: TimeSource): Debouncer =
  if delay <= initDuration():
    raise newException(DebounceConfigError, "debounce delay must be positive")
  Debouncer(delay: delay, timeSource: timeSource)

proc initDebouncer*(delay: Duration): Debouncer =
  initDebouncer(delay = delay, timeSource = initTimeSource())

proc call*(debouncer: var Debouncer) =
  debouncer.pending = true
  debouncer.lastCall = debouncer.timeSource.now()

proc ready*(debouncer: Debouncer): bool =
  debouncer.pending and debouncer.timeSource.now() - debouncer.lastCall >= debouncer.delay

proc consumeReady*(debouncer: var Debouncer): bool =
  if debouncer.ready():
    debouncer.pending = false
    return true
  false

proc cancel*(debouncer: var Debouncer) =
  debouncer.pending = false
  debouncer.lastCall = initDuration()
