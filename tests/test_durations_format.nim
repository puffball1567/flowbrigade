import std/[times, unittest]

import flowbrigade/durations

suite "formatDuration":
  test "formats zero as seconds":
    check formatDuration(initDuration()) == "0s"

  test "formats milliseconds":
    check formatDuration(initDuration(milliseconds = 250)) == "250ms"

  test "formats seconds":
    check formatDuration(initDuration(seconds = 2)) == "2s"

  test "formats minutes":
    check formatDuration(initDuration(minutes = 5)) == "5m"

  test "formats hours":
    check formatDuration(initDuration(hours = 3)) == "3h"

  test "formats days as fixed 24 hour periods":
    check formatDuration(initDuration(days = 2)) == "2d"

  test "formats compound durations compactly":
    check formatDuration(initDuration(hours = 1, minutes = 30)) == "1h30m"

  test "omits zero components":
    check formatDuration(initDuration(days = 1, seconds = 5)) == "1d5s"

  test "keeps millisecond remainder instead of using decimals":
    check formatDuration(initDuration(milliseconds = 1500)) == "1s500ms"

  test "formats microseconds when needed":
    check formatDuration(initDuration(microseconds = 750)) == "750us"

  test "formats nanoseconds when needed":
    check formatDuration(initDuration(nanoseconds = 25)) == "25ns"

  test "formats mixed subsecond precision":
    check formatDuration(initDuration(microseconds = 1250)) == "1ms250us"

  test "formats full precision compound durations":
    check formatDuration(initDuration(
      days = 1,
      hours = 2,
      minutes = 3,
      seconds = 4,
      milliseconds = 5,
      microseconds = 6,
      nanoseconds = 7
    )) == "1d2h3m4s5ms6us7ns"

  test "formats negative durations":
    check formatDuration(initDuration(hours = -1, minutes = -30)) == "-1h30m"
