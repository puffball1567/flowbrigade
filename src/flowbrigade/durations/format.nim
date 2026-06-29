import std/[strutils, times]

const units = [
  ("d", 24'i64 * 60'i64 * 60'i64 * 1_000_000_000'i64),
  ("h", 60'i64 * 60'i64 * 1_000_000_000'i64),
  ("m", 60'i64 * 1_000_000_000'i64),
  ("s", 1_000_000_000'i64),
  ("ms", 1_000_000'i64),
  ("us", 1_000'i64),
  ("ns", 1'i64),
]

proc formatDuration*(duration: Duration): string =
  var remaining = duration.inNanoseconds
  var prefix = ""
  if remaining < 0:
    prefix = "-"
    remaining = -remaining
  if remaining == 0:
    return "0s"

  var parts: seq[string] = @[]
  for (unit, nanos) in units:
    let count = remaining div nanos
    if count > 0:
      parts.add($count & unit)
      remaining = remaining mod nanos

  prefix & parts.join("")
