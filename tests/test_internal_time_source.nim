import std/[times, unittest]

import flowbrigade/internal/time_source

suite "internal time source":
  test "manual time source starts at zero by default":
    let time = initManualTimeSource()

    check time.now() == initDuration()

  test "manual time source can start at a custom duration":
    let time = initManualTimeSource(initDuration(seconds = 5))

    check time.now() == initDuration(seconds = 5)

  test "manual time source advances deterministically":
    let time = initManualTimeSource()

    time.advance(initDuration(milliseconds = 250))
    time.advance(initDuration(milliseconds = 750))

    check time.now() == initDuration(seconds = 1)

  test "manual time source rejects negative advances":
    let time = initManualTimeSource()

    expect TimeSourceError:
      time.advance(initDuration(milliseconds = -1))

  test "monotonic time source never moves backwards":
    let time = initTimeSource()
    let before = time.now()
    let after = time.now()

    check after >= before
