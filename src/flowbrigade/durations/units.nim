import std/times

proc ns*(value: int): Duration =
  initDuration(nanoseconds = value)

proc us*(value: int): Duration =
  initDuration(microseconds = value)

proc ms*(value: int): Duration =
  initDuration(milliseconds = value)

proc sec*(value: int): Duration =
  initDuration(seconds = value)

proc min*(value: int): Duration =
  initDuration(minutes = value)

proc hr*(value: int): Duration =
  initDuration(hours = value)

proc day*(value: int): Duration =
  initDuration(days = value)
