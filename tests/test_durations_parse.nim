import std/[times, unittest]

import flowbrigade/durations

suite "parseDuration":
  test "parses zero":
    check parseDuration("0s") == initDuration()

  test "parses milliseconds":
    check parseDuration("250ms") == initDuration(milliseconds = 250)

  test "parses microseconds":
    check parseDuration("750us") == initDuration(microseconds = 750)

  test "parses nanoseconds":
    check parseDuration("25ns") == initDuration(nanoseconds = 25)

  test "parses seconds":
    check parseDuration("2s") == initDuration(seconds = 2)

  test "parses minutes":
    check parseDuration("5m") == initDuration(minutes = 5)

  test "parses hours":
    check parseDuration("3h") == initDuration(hours = 3)

  test "parses days as fixed 24 hour periods":
    check parseDuration("2d") == initDuration(days = 2)

  test "parses compact compound durations":
    check parseDuration("1h30m") == initDuration(hours = 1, minutes = 30)

  test "parses compound durations with spaces":
    check parseDuration("1h 30m 250ms") ==
      initDuration(hours = 1, minutes = 30, milliseconds = 250)

  test "parses spaces between values and units":
    check parseDuration("1 h 30 m") == initDuration(hours = 1, minutes = 30)

  test "trims surrounding whitespace":
    check parseDuration("  30s  ") == initDuration(seconds = 30)

  test "parses positive signed durations":
    check parseDuration("+1h30m") == initDuration(hours = 1, minutes = 30)

  test "parses negative signed durations":
    check parseDuration("-1h30m") == initDuration(hours = -1, minutes = -30)

  test "parses signed durations with internal spaces":
    check parseDuration("-1 h 30 m") == initDuration(hours = -1, minutes = -30)

  test "parses decimal seconds":
    check parseDuration("1.5s") == initDuration(milliseconds = 1500)

  test "parses decimal minutes":
    check parseDuration("1.5m") == initDuration(seconds = 90)

  test "parses decimal milliseconds":
    check parseDuration("1.25ms") == initDuration(microseconds = 1250)

  test "adds repeated units":
    check parseDuration("1m60s") == initDuration(minutes = 2)

  test "rejects empty input":
    expect DurationParseError:
      discard parseDuration("")

  test "rejects whitespace only input":
    expect DurationParseError:
      discard parseDuration("   ")

  test "rejects values without units":
    expect DurationParseError:
      discard parseDuration("10")

  test "rejects units without values":
    expect DurationParseError:
      discard parseDuration("ms")

  test "rejects unknown units":
    expect DurationParseError:
      discard parseDuration("10fortnights")

  test "rejects calendar month units":
    expect DurationParseError:
      discard parseDuration("1mo")

  test "rejects calendar year units":
    expect DurationParseError:
      discard parseDuration("1y")

  test "rejects embedded negative signs":
    expect DurationParseError:
      discard parseDuration("1h-30m")

  test "rejects embedded plus signs":
    expect DurationParseError:
      discard parseDuration("1h+30m")

  test "rejects uppercase units":
    expect DurationParseError:
      discard parseDuration("1H")

  test "rejects malformed decimal values":
    expect DurationParseError:
      discard parseDuration("1.2.3s")

  test "rejects decimal points without fractions":
    expect DurationParseError:
      discard parseDuration("1.s")

  test "rejects trailing words":
    expect DurationParseError:
      discard parseDuration("1s ago")

  test "rejects overflowing values":
    expect DurationParseError:
      discard parseDuration("92233720368547758070s")

  test "rejects inputs longer than the configured maximum":
    expect DurationParseError:
      discard parseDuration("1s", maxLength = 1)

  test "accepts inputs at the configured maximum length":
    check parseDuration("1s", maxLength = 2) == initDuration(seconds = 1)
