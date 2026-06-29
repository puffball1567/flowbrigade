import std/[times, unittest]

import flowbrigade/durations

suite "duration unit helpers":
  test "builds milliseconds with ms":
    check 250.ms == initDuration(milliseconds = 250)

  test "builds seconds with sec":
    check 2.sec == initDuration(seconds = 2)

  test "builds minutes with min":
    check 3.min == initDuration(minutes = 3)

  test "builds hours with hr":
    check 4.hr == initDuration(hours = 4)

  test "builds days with day":
    check 5.day == initDuration(days = 5)

  test "builds negative durations":
    check (-1).sec == initDuration(seconds = -1)
