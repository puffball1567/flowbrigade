import std/[math, parseutils, strutils, times]

import ./errors

const unitNanos = [
  ("ns", 1'i64),
  ("us", 1_000'i64),
  ("ms", 1_000_000'i64),
  ("s", 1_000_000_000'i64),
  ("m", 60'i64 * 1_000_000_000'i64),
  ("h", 60'i64 * 60'i64 * 1_000_000_000'i64),
  ("d", 24'i64 * 60'i64 * 60'i64 * 1_000_000_000'i64),
]

const DefaultMaxDurationInputLength* = 4096

proc parseUnit(input: string; pos: var int): int64 =
  for (unit, nanos) in unitNanos:
    if input.continuesWith(unit, pos):
      inc pos, unit.len
      return nanos
  raise newException(DurationParseError, "unknown duration unit")

proc toDuration(totalNanos: int64): Duration =
  initDuration(nanoseconds = totalNanos)

proc checkedParseInt(input: string; value: var int; pos: int): int =
  try:
    parseInt(input, value, pos)
  except ValueError as exc:
    raise newException(DurationParseError, exc.msg)

proc parseDuration*(input: string; maxLength = DefaultMaxDurationInputLength): Duration =
  if maxLength < 1:
    raise newException(DurationParseError, "maxLength must be positive")
  if input.len > maxLength:
    raise newException(DurationParseError, "duration input is too long")

  var text = ""
  for ch in input:
    if not ch.isSpaceAscii:
      text.add(ch)
  if text.len == 0:
    raise newException(DurationParseError, "duration cannot be empty")

  var pos = 0
  var total = 0'i64
  var parsedAny = false
  var sign = 1'i64

  if text[pos] == '-':
    sign = -1
    inc pos
  elif text[pos] == '+':
    inc pos

  if pos >= text.len:
    raise newException(DurationParseError, "duration value expected")

  while pos < text.len:
    if text[pos] == '-' or text[pos] == '+':
      raise newException(DurationParseError, "duration signs are only allowed at the start")

    let numberStart = pos
    var whole = 0
    let wholeLen = checkedParseInt(text, whole, pos)
    if wholeLen == 0:
      raise newException(DurationParseError, "duration value expected")
    pos += wholeLen

    var value = float(whole)
    if pos < text.len and text[pos] == '.':
      inc pos
      let fractionStart = pos
      var fraction = 0
      let fractionLen = checkedParseInt(text, fraction, pos)
      if fractionLen == 0:
        raise newException(DurationParseError, "duration decimal fraction expected")
      pos += fractionLen
      if pos < text.len and text[pos] == '.':
        raise newException(DurationParseError, "malformed duration decimal value")
      value += float(fraction) / pow(10.0, float(pos - fractionStart))

    if pos == numberStart:
      raise newException(DurationParseError, "duration value expected")

    let unit = parseUnit(text, pos)
    if value > float(high(int64)) / float(unit):
      raise newException(DurationParseError, "duration is too large")
    let component = int64(value * float(unit))
    if component > high(int64) - total:
      raise newException(DurationParseError, "duration is too large")
    total += component
    parsedAny = true

  if not parsedAny:
    raise newException(DurationParseError, "duration value expected")

  toDuration(total * sign)
