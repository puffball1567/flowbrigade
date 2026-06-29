import std/[times, unittest]

import flowbrigade/debounce
import flowbrigade/internal/time_source

suite "debounce":
  test "is not ready before any call":
    let time = initManualTimeSource()
    var debouncer = initDebouncer(delay = initDuration(seconds = 1), timeSource = time)

    check not debouncer.ready()
    check not debouncer.consumeReady()

  test "becomes ready after the delay from the latest call":
    let time = initManualTimeSource()
    var debouncer = initDebouncer(delay = initDuration(seconds = 1), timeSource = time)

    debouncer.call()
    time.advance(initDuration(milliseconds = 500))
    check not debouncer.ready()

    debouncer.call()
    time.advance(initDuration(milliseconds = 999))
    check not debouncer.ready()

    time.advance(initDuration(milliseconds = 1))
    check debouncer.ready()

  test "consumeReady returns true once":
    let time = initManualTimeSource()
    var debouncer = initDebouncer(delay = initDuration(seconds = 1), timeSource = time)

    debouncer.call()
    time.advance(initDuration(seconds = 1))

    check debouncer.consumeReady()
    check not debouncer.consumeReady()
    check not debouncer.ready()

  test "cancel clears pending work":
    let time = initManualTimeSource()
    var debouncer = initDebouncer(delay = initDuration(seconds = 1), timeSource = time)

    debouncer.call()
    debouncer.cancel()
    time.advance(initDuration(seconds = 1))

    check not debouncer.ready()

  test "rejects invalid debounce delay":
    let time = initManualTimeSource()

    expect DebounceConfigError:
      discard initDebouncer(delay = initDuration(), timeSource = time)

  test "default constructor uses a real time source":
    var debouncer = initDebouncer(delay = initDuration(seconds = 1))

    check not debouncer.ready()
    debouncer.call()
    check not debouncer.ready()
